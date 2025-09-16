local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;

[
  esp.admission('ingress-router-set-dualstack', params.namespace) {
    spec: {
      mutating: true,
      template: importstr 'espejote-templates/ingress-router-dualstack.jsonnet',
      webhookConfiguration: {
        rules: [
          {
            apiGroups: [ '' ],
            apiVersions: [ '*' ],
            operations: [ 'CREATE' ],
            resources: [ 'pods' ],
          },
        ],
        objectSelector: params.patchDualStack.objectSelector,
      },
    },
  },
]
