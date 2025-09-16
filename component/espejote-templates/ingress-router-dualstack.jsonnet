local esp = import 'espejote.libsonnet';
local admission = esp.ALPHA.admission;

local pod = admission.admissionRequest().object;

local cids = std.find('router', std.map(function(c) c.name, pod.spec.containers));
assert std.length(cids) == 1 : "Expected to find a single container with name 'router'";
local containerIndex = cids[0];

// Asserts against null.
// We could just add an empty array as env before the patch and don't fail but it might be better for someone to check what changed.
local env = std.get(pod.spec.containers[containerIndex], 'env');
assert std.isArray(env) : 'Expected container env to be an array, is: %s' % std.type(env);

// Try to find ROUTER_IP_V4_V6_MODE envvar in the container
// Fail if we find it more than once.
local eids = std.find('ROUTER_IP_V4_V6_MODE', std.map(function(e) e.name, pod.spec.containers[containerIndex].env));
assert std.length(eids) <= 1 : "Expected to find at most one envvar named 'ROUTER_IP_V4_V6_MODE'";

local containerPath = '/spec/containers/%s' % containerIndex;
local env_v4v6 = { name: 'ROUTER_IP_V4_V6_MODE', value: 'v4v6' };

// Overwrite or add the ROUTER_IP_V4_V6_MODE envvar in the container
local patch = if std.length(eids) == 1 then
  admission.jsonPatchOp(
    'replace',
    containerPath + '/env/%d' % eids[0],
    env_v4v6,
  )
else
  admission.jsonPatchOp(
    'add',
    containerPath + '/env/-',
    env_v4v6,
  );

admission.patched('added dualstack env', admission.assertPatch([ patch ]))
