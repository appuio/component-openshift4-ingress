local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;

{
  [name]: kube._Object('operator.openshift.io/v1', 'IngressController', name) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: params.ingressControllers[name],
  }
  for name in std.objectFields(params.ingressControllers)
}
