local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_ingress;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-ingress', params.namespace);

{
  'openshift4-ingress': app,
}
