let apiKey: string | undefined;
export function setApiKey(key: string) {
  apiKey = key;
}

export function getApiKeyMeta() {
  if (!apiKey) {
    return {};
  }
  return {
    headers: {
      "api-key": apiKey,
    },
  };
}
