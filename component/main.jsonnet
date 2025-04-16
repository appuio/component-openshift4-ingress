local acme = import 'acme.libsonnet';
local cm = import 'lib/cert-manager.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local po = import 'lib/patch-operator.libsonnet';
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

local defaultNamespacePatch = po.Patch(kube.Namespace('default'), {
  metadata: {
    labels: {
      'network.openshift.io/policy-group': 'hostNetwork',
    },
  },
});

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

local ingressControllerManifests = {
  local acmeCertName = 'acme-wildcard-' + name,
  local annotations =
    if std.objectHas(params.ingressControllerAnnotations, name) then
      params.ingressControllerAnnotations[name],
  local epps = std.get(
    params.ingressControllers[name],
    'endpointPublishingStrategy',
    { type: 'Private' },
  ),
  local is_cloudscale_lbaas =
    std.get(epps, 'type', '') == 'cloudscale-lbaas',
  local epps_cloudscale = std.get(epps, 'cloudscale', {}),
  local cs_proto = if is_cloudscale_lbaas then
    std.get(epps_cloudscale, 'protocol', 'PROXY'),

  [name]: {
    ic: kube._Object('operator.openshift.io/v1', 'IngressController', name) {
      metadata+: {
        namespace: params.namespace + '-operator',
        [if annotations != null then 'annotations']: annotations,
      },
      spec: {
        [if hasAcmeSupport then 'defaultCertificate']: {
          name: acmeCertName,
        },
      } + params.ingressControllers[name] + {
        [if std.get(epps, 'type', '') == 'cloudscale-lbaas' then
          'endpointPublishingStrategy']:
          if name == 'default' then {
            hostNetwork: {
              protocol: cs_proto,
            },
            type: 'HostNetwork',
          } else {
            private: {
              protocol: cs_proto,
            },
            type: 'Private',
          },
      },
    },

    cert: if usesAcme(name) then
      acme.cert(acmeCertName, [ '*.' + params.ingressControllers[name].domain ]),

    lb_service: if is_cloudscale_lbaas then
      local cs_vip = std.get(epps_cloudscale, 'floatingIP');
      kube.Service('appuio-%s-lb' % name) {
        metadata+: {
          // NOTE: this is required so the service object can be applied
          // during bootstrap.
          namespace: params.namespace,
          annotations+:
            {
              // Set force-hostname if no floating IP is configured.
              // Assumption: Cilium doesn't understand ipMode=Proxy yet, so we
              // need to force hostname, since we expect that DNS name for the
              // ingress resolves to the service IP when no floating IP is
              // configured. NOTE: this can be overridden via
              // `serviceAnnotations`.
              [if cs_vip == null then 'k8s.cloudscale.ch/loadbalancer-force-hostname']:
                'ingress.%s' %
                std.join('.', std.split(params.ingressControllers[name].domain, '.')[1:]),
              // Configure `floating-ips` annotation if
              // `cloudscale.floatingIP` is set.
              [if cs_vip != null then 'k8s.cloudscale.ch/loadbalancer-floating-ips']:
                std.manifestJsonMinified([ cs_vip ]),
              // Configure LB protocol to proxyv2 if ingress is configured
              // with PROXY protocol, tcp otherwise.
              'k8s.cloudscale.ch/loadbalancer-pool-protocol':
                if cs_proto == 'PROXY' then 'proxyv2' else 'tcp',
              // TODO(sg): Update default annotations to set custom http check
              // with Red Hat-recommended check on HAproxy stats port. TBD how
              // this will look, since we don't expose the stats port in the
              // LB service and don't know the port number for `Private`
              // ingresses a priori.
            } + std.get(epps_cloudscale, 'serviceAnnotations', {}),
          labels+: std.get(epps_cloudscale, 'serviceLabels', {}),
        },
        spec: {
          type: 'LoadBalancer',
          externalTrafficPolicy: 'Local',
          ports: [
            {
              name: 'http',
              port: 80,
              protocol: 'TCP',
              targetPort: 'http',
            },
            {
              name: 'https',
              port: 443,
              protocol: 'TCP',
              targetPort: 'https',
            },
          ],
          selector: {
            'ingresscontroller.operator.openshift.io/deployment-ingresscontroller': name,
          },

        },
      },
  }
  for name in ingressControllers
};


if std.length(ingressControllerManifests) > 0 then
  {
    local manifests = ingressControllerManifests[name],
    [name]: std.prune([ manifests.ic, manifests.cert ])
    for name in std.objectFields(ingressControllerManifests)
  } +
  {
    local manifests = ingressControllerManifests[name],
    ['%s_lb_service' % name]: manifests.lb_service
    for name in std.objectFields(ingressControllerManifests)
    if ingressControllerManifests[name].lb_service != null
  }
  + {
    '00_label_patches': defaultNamespacePatch,
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
