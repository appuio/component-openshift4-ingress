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

local monNS = 'syn-mon-%s' % [ params.namespace ];

local saRef = {
  kind: 'ServiceAccount',
  name: 'prometheus-monitoring',
  namespace: 'syn-monitoring',
};

local ingressServiceMonitor(name) = prometheus.ServiceMonitor('ingress-controller-%s' % [ name ]) {
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
          serverName: 'router-internal-%s.openshift-ingress.svc' % [ name ],
        },
      },
    ],
    selector: {
      matchLabels: {
        'ingresscontroller.operator.openshift.io/owning-ingresscontroller': name,
      },
    },
    namespaceSelector: {
      matchNames: [ 'openshift-ingress' ],
    },
  },
};

local ingressControllers =
  if params.ingressControllers != null
  then std.objectFields(params.ingressControllers)
  else [];


{
  '20_monitoring/00_namespace': prometheus.RegisterNamespace(
    kube.Namespace(monNS)
  ),
  '20_monitoring/10_ingress_clusterrole': clusterRole,
  '20_monitoring/10_ingress_clusterrolebinding': kube.ClusterRoleBinding('openshift-ingress-metrics') {
    roleRef_: clusterRole,
    subjects: [ saRef ],
  },

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
  '20_monitoring/10_serviceMonitors_ingress': [ ingressServiceMonitor(ing) for ing in ingressControllers ],
}
