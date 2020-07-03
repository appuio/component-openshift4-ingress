local acme = import 'acme.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;
local usesAcme(name) = !std.objectHas(params.ingressControllers[name], 'defaultCertificate');
local anyControllerUsesAcme = std.foldl(
  function(x, field) x || usesAcme(field),
  std.objectFields(params.ingressControllers),
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
        defaultCertificate: {
          name: acmeCertName,
        },
      } + params.ingressControllers[name],
    }] +
    if usesAcme(name) then
      [
        acme.cert(acmeCertName, ['*.' + params.ingressControllers[name].domain]),
      ] else []
  for name in std.objectFields(params.ingressControllers)
} + {
  [if anyControllerUsesAcme then 'acmeIssuer']: acme.issuer(),
}
