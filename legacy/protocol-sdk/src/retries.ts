async function wait(delayMs: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, delayMs);
  });
}

const retryInternal = async <T>({
  tryFn,
  maxTries = 3,
  atTry,
  linearBackoffMS = 200,
  shouldRetryOnError = () => true,
}: {
  tryFn: () => T;
  maxTries?: number;
  atTry: number;
  linearBackoffMS?: number;
  shouldRetryOnError?: (err: any) => boolean;
}): Promise<T> => {
  try {
    return await tryFn();
  } catch (err: any) {
    if (shouldRetryOnError(err)) {
      if (atTry <= maxTries) {
        await wait(atTry * linearBackoffMS);
        return await retryInternal({
          tryFn,
          maxTries,
          atTry: atTry + 1,
          linearBackoffMS,
          shouldRetryOnError,
        });
      }
    }
    throw err;
  }
};

export const retriesGeneric = async <T>(params: {
  tryFn: () => T;
  maxTries?: number;
  linearBackoffMS?: number;
  shouldRetryOnError?: (err: any) => boolean;
}) => {
  return retryInternal({
    ...params,
    atTry: 1,
  });
};
