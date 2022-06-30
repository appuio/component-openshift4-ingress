local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local prometheus = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_ingress;

local clusterRole = kube.ClusterRole('openshift-ingress-metrics') {
  rules: [
    {
      apiGroups: [ 'route.openshift.io' ],
      resources: [ 'routers/metrics' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

{
  '20_monitoring/00_namespace': prometheus.RegisterNamespace(
    kube.Namespace('syn-mon-%s' % [ params.namespace ])
  ),
  '20_monitoring/10_serviceMonitor_operator': prometheus.ServiceMonitor('ingress-operator') {
    metadata+: {
      namespace: 'syn-mon-%s' % [ params.namespace ],
    },
    spec: {
      endpoints: [
        {
          bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
          interval: '30s',
          port: 'metrics',
          scheme: 'https',
          tlsConfig: {
            caFile: '/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt',
            serverName: 'metrics.openshift-ingress-operator.svc',
          },
        },
      ],
      jobLabel: 'name',
      selector: {
        matchLabels: {
          name: 'ingress-operator',
        },
      },
      namespaceSelector: {
        matchNames: [ 'openshift-ingress-operator' ],
      },
    },
  },
  '20_monitoring/10_ingress_clusterrole': clusterRole,
  '20_monitoring/10_ingress_clusterrolebinding': kube.ClusterRoleBinding('openshift-ingress-metrics') {
    roleRef_: clusterRole,
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'prometheus-monitoring',
        namespace: 'syn-monitoring',
      },
    ],
  },
  '20_monitoring/10_serviceMonitor_ingress': prometheus.ServiceMonitor('ingress-controller-default') {
    metadata+: {
      namespace: 'syn-mon-%s' % [ params.namespace ],
    },
    spec: {
      endpoints: [
        {
          bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
          interval: '30s',
          port: 'metrics',
          scheme: 'https',
          tlsConfig: {
            caFile: '/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt',
            serverName: 'router-internal-default.openshift-ingress.svc',
          },
        },
      ],
      selector: {
        matchLabels: {
          'ingresscontroller.operator.openshift.io/owning-ingresscontroller': 'default',
        },
      },
      namespaceSelector: {
        matchNames: [ 'openshift-ingress' ],
      },
    },
  },
}
