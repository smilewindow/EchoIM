let wsConnected = false

export function setWsConnected(connected: boolean) {
  wsConnected = connected
}

export function isWsConnected() {
  return wsConnected
}
