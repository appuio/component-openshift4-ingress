local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local prometheus = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_ingress;


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
