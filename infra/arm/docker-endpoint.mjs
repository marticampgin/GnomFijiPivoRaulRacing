export function assertLocalDockerEndpoint(context, environment = process.env) {
  // Docker gives an explicit context precedence over DOCKER_HOST.
  const endpoint = environment.DOCKER_CONTEXT
    ? context?.Endpoints?.docker?.Host
    : environment.DOCKER_HOST || context?.Endpoints?.docker?.Host;
  if (typeof endpoint !== 'string' || !endpoint.startsWith('unix://')) {
    throw new Error('Use a local Docker Unix socket, not a remote daemon');
  }
  return endpoint;
}
