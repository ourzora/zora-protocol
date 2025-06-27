let apiKey: string | undefined;
export function setApiKey(key: string | undefined) {
  apiKey = key;
}

export function getApiKey() {
  return apiKey;
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
