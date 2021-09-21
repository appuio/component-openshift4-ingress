local acme = import 'acme.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local resourcelocker = import 'lib/resource-locker.libjsonnet';
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

local defaultNamespacePatch = resourcelocker.Patch(kube.Namespace('default'), {
  metadata: {
    labels: {
      'network.openshift.io/policy-group': 'hostNetwork',
    },
  },
});

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
    '00_label_patches': defaultNamespacePatch,
    [if anyControllerUsesAcme then 'acmeIssuer']: acme.issuer,
  }
else
  // if no ingressControllers are configured, only emit an empty `.gitkeep`
  // file.
  {
    '.gitkeep': {},
  }
