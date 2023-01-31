local kube = import 'lib/kube.libjsonnet';

local cluster_reader =
  kube.ClusterRole('syn:openshift4-ingress:cluster-reader') {
    metadata+: {
      labels+: {
        'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
      },
    },
    rules: [
      {
        apiGroups: [ 'operator.openshift.io' ],
        resources: [ 'ingresscontrollers' ],
        verbs: [
          'get',
          'list',
          'watch',
        ],
      },
    ],
  };

[
  cluster_reader,
]
