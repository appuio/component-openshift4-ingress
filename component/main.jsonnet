local acme = import 'acme.libsonnet';
local cm = import 'lib/cert-manager.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local espejote = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;
local hasAcmeSupport = std.objectHas(params.cloud, params.cloud.provider);
local ingressControllers =
  if params.ingressControllers != null
  then std.objectFields(params.ingressControllers)
  else [];
local usesAcme(name) = hasAcmeSupport && !std.objectHas(params.ingressControllers[name], 'defaultCertificate');
local anyControllerUsesAcme = std.foldl(
  function(x, field) x || usesAcme(field),
  ingressControllers,
  false,
);

local _patchDefaultNamespace = 'patch-default-namespace';
local patchDefaultNamespace = [
  espejote.managedResource(_patchDefaultNamespace, params.namespace) {
    metadata+: {
      annotations+: {
        'syn.tools/description': |||
          Patches the default namespace to add the hostNetwork policy group.
        |||,
      },
    },
    spec: {
      triggers: [
        {
          name: 'namespace',
          watchResource: {
            apiVersion: 'v1',
            kind: 'Namespace',
            name: 'default',
          },
        },
      ],
      serviceAccountRef: {
        name: _patchDefaultNamespace,
      },
      template: std.manifestJson({
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          labels: {
            'network.openshift.io/policy-group': 'hostNetwork',
          },
          name: 'default',
        },
      }),
    },
  },
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        'app.kubernetes.io/name': _patchDefaultNamespace,
        'managedresource.espejote.io/name': _patchDefaultNamespace,
      },
      name: _patchDefaultNamespace,
      namespace: params.namespace,
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      labels: {
        'app.kubernetes.io/name': _patchDefaultNamespace,
        'managedresource.espejote.io/name': _patchDefaultNamespace,
      },
      name: 'ingress:%s' % _patchDefaultNamespace,
    },
    rules: [
      {
        apiGroups: [ '' ],
        resources: [ 'namespaces' ],
        resourceNames: [ 'default' ],
        verbs: [ '*' ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      labels: {
        'app.kubernetes.io/name': _patchDefaultNamespace,
        'managedresource.espejote.io/name': _patchDefaultNamespace,
      },
      name: 'ingress:%s' % _patchDefaultNamespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'ingress:%s' % _patchDefaultNamespace,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: _patchDefaultNamespace,
        namespace: params.namespace,
      },
    ],
  },
];

local isTlsSecret(secret) =
  local secretKeys = std.set(std.objectFields(secret.stringData));
  local keyDiff = std.setDiff(secretKeys, std.set([
    'ca.crt',
    'tls.crt',
    'tls.key',
  ]));
  secret.type == 'kubernetes.io/tls' && std.length(keyDiff) == 0;

local extraSecrets = std.filter(
  function(it) it != null,
  [
    local scontent = params.secrets[s];
    local secret = kube.Secret(kube.hyphenate(s)) {
      type: 'kubernetes.io/tls',
      metadata+: {
        namespace: params.namespace,
      },
    } + com.makeMergeable(scontent);
    if scontent != null then
      if isTlsSecret(secret) then
        secret {
          stringData+: {
            [if 'tls.key' in secret.stringData then 'tls.key']: super['tls.key'] + '\n',
            [if 'tls.crt' in secret.stringData then 'tls.crt']: super['tls.crt'] + '\n',
            [if 'ca.crt' in secret.stringData then 'ca.crt']: super['ca.crt'] + '\n',
          },
        }
      else
        error "Invalid secret definition for key '%s'. This component expects secret definitions which are valid for kubernetes.io/tls secrets." % s
    for s in std.objectFields(params.secrets)
  ]
);

local extraCerts = std.filter(
  function(it) it != null,
  [
    local cname = kube.hyphenate(c);
    local cert = params.cert_manager_certs[c];
    if cert != null then
      cm.cert(cname) {
        metadata+: {
          namespace: params.namespace,
        },
        spec+: {
          secretName: '%s' % cname,
        },
      } + com.makeMergeable(cert)
    for c in std.objectFields(params.cert_manager_certs)
  ]
);


if std.length(ingressControllers) > 0 then
  {
    local acmeCertName = 'acme-wildcard-' + name,
    local annotations =
      if std.objectHas(params.ingressControllerAnnotations, name) then
        params.ingressControllerAnnotations[name],

    [name]:
      [ kube._Object('operator.openshift.io/v1', 'IngressController', name) {
        metadata+: {
          namespace: params.namespace + '-operator',
          [if annotations != null then 'annotations']: annotations,
        },
        spec: {
          [if hasAcmeSupport then 'defaultCertificate']: {
            name: acmeCertName,
          },
        } + params.ingressControllers[name],
      } ] +
      if usesAcme(name) then
        [
          acme.cert(acmeCertName, [ '*.' + params.ingressControllers[name].domain ]),
        ] else []
    for name in ingressControllers
  } + {
    '00_label_patches': patchDefaultNamespace,
    '01_aggregated_clusterroles': (import 'aggregated-clusterroles.libsonnet'),
    [if anyControllerUsesAcme then 'acmeIssuer']: acme.issuer,
    [if std.length(extraSecrets) > 0 then '10_extra_secrets']: extraSecrets,
    [if std.length(extraCerts) > 0 then '10_extra_certificates']: extraCerts,
  }
else
  // if no ingressControllers are configured, only emit an empty `.gitkeep`
  // file.
  {
    '.gitkeep': {},
  }
