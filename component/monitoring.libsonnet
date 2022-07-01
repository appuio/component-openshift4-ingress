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

local serviceMonitor(name) = prometheus.ServiceMonitor(name) {
  local sm = self,

  service:: '',
  targetNamespace:: '',
  scheme:: 'https',
  selector:: {},
  spec: {
    endpoints: [
      {
        bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
        interval: '30s',
        port: 'metrics',
        scheme: sm.scheme,
        tlsConfig: {
          caFile: '/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt',
          serverName: '%s.%s.svc' % [ sm.service, sm.targetNamespace ],
        },
      },
    ],
    namespaceSelector: {
      matchNames: [ sm.targetNamespace ],
    },
    selector: sm.selector,
  },
};

local operatorServiceMonitor = serviceMonitor('ingress-operator') {
  metadata+: {
    namespace: 'syn-mon-%s' % [ params.namespace ],
  },
  service: 'metrics',
  targetNamespace: 'openshift-ingress-operator',
  selector: {
    matchLabels: {
      name: 'ingress-operator',
    },
  },
  spec+: {
    jobLabel: 'name',
  },
};

local ingressServiceMonitor(name) = serviceMonitor('ingress-controller-%s' % [ name ]) {
  metadata+: {
    namespace: monNS,
  },
  service: 'router-internal-%s' % [ name ],
  targetNamespace: 'openshift-ingress',
  selector: {
    matchLabels: {
      'ingresscontroller.operator.openshift.io/owning-ingresscontroller': name,
    },
  },
};

local ingressControllers =
  if params.ingressControllers != null
  then std.objectFields(params.ingressControllers)
  else [];


local serviceMonitors = [ operatorServiceMonitor ] + [ ingressServiceMonitor(ing) for ing in ingressControllers ];

{
  '20_monitoring/00_namespace': prometheus.RegisterNamespace(
    kube.Namespace(monNS)
  ),
  '20_monitoring/10_ingress_clusterrole': clusterRole,
  '20_monitoring/10_ingress_clusterrolebinding': kube.ClusterRoleBinding('openshift-ingress-metrics') {
    roleRef_: clusterRole,
    subjects: [ saRef ],
  },
  '20_monitoring/10_serviceMonitors': std.filter(
    function(it) it != null,
    [
      if com.getValueOrDefault(params.monitoring.enableServiceMonitors, sm.metadata.name, true) then sm
      for sm in serviceMonitors
    ]
  ),
}
