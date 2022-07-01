local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local prometheus = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_ingress;

local promInstance =
  if params.monitoring.instance != '' then
    params.monitoring.instance
  else
    inv.parameters.prometheus.defaultInstance;

local clusterRole = kube.ClusterRole('openshift-ingress-metrics') {
  rules: [
    {
      apiGroups: [ 'route.openshift.io' ],
      resources: [ 'routers/metrics' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local operatorServiceMonitor = prometheus.ServiceMonitor('ingress-operator') {
  local sm = self,

  targetNamespace: 'openshift-ingress-operator',
  endpoints: {
    metrics: prometheus.ServiceMonitorHttpsEndpoint('metrics.%s.svc' % [ sm.targetNamespace ]) {
      relabelings: [ prometheus.DropRuntimeMetrics ],
    },
  },
  selector: {
    matchLabels: {
      name: 'ingress-operator',
    },
  },
  spec+: {
    jobLabel: 'name',
  },
};

local ingressServiceMonitor(name) = prometheus.ServiceMonitor('ingress-controller-%s' % [ name ]) {
  local sm = self,

  targetNamespace: 'openshift-ingress',
  endpoints: {
    router: prometheus.ServiceMonitorHttpsEndpoint('router-internal-%s.%s.svc' % [ name, sm.targetNamespace ]) {
      relabelings: [ prometheus.DropRuntimeMetrics ],
    },
  },
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
local monNS = 'syn-monitoring-%s' % [ params.namespace ];

{
  '20_monitoring/00_namespace': prometheus.RegisterNamespace(
    kube.Namespace(monNS),
    instance=promInstance
  ),
  '20_monitoring/10_ingress_clusterrole': clusterRole,
  '20_monitoring/10_ingress_clusterrolebinding': kube.ClusterRoleBinding('openshift-ingress-metrics') {
    roleRef_: clusterRole,
    subjects: [ prometheus.ServiceAccountRef(instance=promInstance) ],
  },
  '20_monitoring/10_serviceMonitors': std.filter(
    function(it) it != null,
    [
      if com.getValueOrDefault(params.monitoring.enableServiceMonitors, sm.metadata.name, true) then
        sm {
          metadata+: {
            namespace: monNS,
          },
        }
      for sm in serviceMonitors
    ]
  ),
}
