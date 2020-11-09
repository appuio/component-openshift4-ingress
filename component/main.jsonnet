local acme = import 'acme.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;
local cloud = inv.parameters.cloud.provider;
local hasAcmeSupport = std.objectHas(params.cloud, cloud);
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

{
  local acmeCertName = 'acme-wildcard-' + name,
  [name]:
    [kube._Object('operator.openshift.io/v1', 'IngressController', name) {
      metadata+: {
        namespace: params.namespace + '-operator',
      },
      spec: {
        [if hasAcmeSupport then defaultCertificate]: {
          name: acmeCertName,
        },
      } + params.ingressControllers[name],
    }] +
    if usesAcme(name) then
      [
        acme.cert(acmeCertName, ['*.' + params.ingressControllers[name].domain]),
      ] else []
  for name in ingressControllers
} + {
  [if anyControllerUsesAcme then 'acmeIssuer']: acme.issuer(),
  [if std.length(ingressControllers) == 0 then '.gitkeep']: {},
}
