import {
  ERROR_CODES,
  type ApiErrorBody,
  type ErrorCode,
  type ErrorEnvelope,
  type SuccessEnvelope,
} from "@omniassist/contracts";

const errorCodeSet: ReadonlySet<string> = new Set(ERROR_CODES);

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isErrorCode(value: unknown): value is ErrorCode {
  return typeof value === "string" && errorCodeSet.has(value);
}

function parseErrorEnvelope(
  payload: unknown,
  responseRequestId: string | null,
  responseStatus: number,
): ErrorEnvelope {
  if (isRecord(payload) && isRecord(payload.error)) {
    const raw = payload.error;
    const details = isRecord(raw.details) ? raw.details : {};
    const body: ApiErrorBody = {
      code: isErrorCode(raw.code) ? raw.code : "INTERNAL_ERROR",
      message: typeof raw.message === "string" ? raw.message : "The request could not be completed.",
      details,
      request_id: typeof raw.request_id === "string" ? raw.request_id : responseRequestId,
      retryable: typeof raw.retryable === "boolean" ? raw.retryable : false,
    };
    return { error: body };
  }

  return {
    error: {
      code: "INTERNAL_ERROR",
      message: "The server returned an invalid error response.",
      details: {},
      request_id: responseRequestId,
      retryable: responseStatus >= 500,
    },
  };
}

export class ApiClientError extends Error {
  readonly code: ErrorCode;
  readonly details: Readonly<Record<string, unknown>>;
  readonly requestId: string | null;
  readonly retryable: boolean;
  readonly status: number;

  constructor(status: number, body: ApiErrorBody) {
    super(body.message);
    this.name = "ApiClientError";
    this.status = status;
    this.code = body.code;
    this.details = body.details;
    this.requestId = body.request_id;
    this.retryable = body.retryable;
  }
}

export type ApiRequestInit = Omit<RequestInit, "body"> & {
  body?: BodyInit | Record<string, unknown> | null;
};

export async function requestApi<TData>(
  input: string | URL,
  init: ApiRequestInit = {},
): Promise<SuccessEnvelope<TData>> {
  const headers = new Headers(init.headers);
  if (!headers.has("accept")) headers.set("accept", "application/json");

  let body: BodyInit | null | undefined;
  if (init.body !== undefined && init.body !== null && typeof init.body === "object" && !(init.body instanceof Blob) && !(init.body instanceof FormData) && !(init.body instanceof URLSearchParams) && !(init.body instanceof ArrayBuffer) && !ArrayBuffer.isView(init.body)) {
    headers.set("content-type", "application/json");
    body = JSON.stringify(init.body);
  } else {
    body = init.body as BodyInit | null | undefined;
  }

  const response = await fetch(input, { ...init, headers, body });
  const requestIdHeader = response.headers.get("x-request-id");
  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  if (!response.ok) {
    const envelope = parseErrorEnvelope(payload, requestIdHeader, response.status);
    throw new ApiClientError(response.status, envelope.error);
  }

  if (!isRecord(payload) || !("data" in payload) || !isRecord(payload.meta)) {
    throw new ApiClientError(response.status, {
      code: "INTERNAL_ERROR",
      message: "The server returned an invalid success response.",
      details: {},
      request_id: requestIdHeader,
      retryable: response.status >= 500,
    });
  }

  const metaRequestId = payload.meta.request_id;
  const meta = {
    ...payload.meta,
    request_id: typeof metaRequestId === "string" ? metaRequestId : requestIdHeader,
  };

  return { data: payload.data as TData, meta };
}

export function apiUrl(path: string): string {
  const base =
    process.env.NEXT_PUBLIC_API_URL ||
    (process.env.NODE_ENV === "production" ? undefined : "http://localhost:8000/api/v1");
  if (!base) throw new Error("NEXT_PUBLIC_API_URL must be configured for production API requests.");
  return `${base.replace(/\/$/, "")}${path}`;
}

const SESSION_KEY = "omniassist_session";
const ACCESS_KEY = "omniassist_access_token";

type StoredSession = UnknownRecord & { access_token?: string; refresh_token?: string };

function storedSession(): StoredSession | null {
  try {
    const raw = window.localStorage.getItem(SESSION_KEY);
    return raw ? (JSON.parse(raw) as StoredSession) : null;
  } catch {
    return null;
  }
}

let renewing: Promise<boolean> | null = null;

/**
 * Swaps the refresh token for a new session. Access tokens last 15 minutes, so without this the
 * app would stop working a quarter of an hour after sign-in. A refresh token works exactly once,
 * so renewals run one at a time, across tabs too: a tab that waited and finds the token already
 * swapped by another tab just uses the new session.
 */
function renewSession(refreshUsed: string | undefined): Promise<boolean> {
  const renew = async () => {
    const current = storedSession();
    if (!current?.refresh_token) return false;
    if (refreshUsed && current.refresh_token !== refreshUsed) return true;
    try {
      const fresh = (await requestApi<StoredSession>(apiUrl("/auth/refresh"), {
        method: "POST",
        body: { refresh_token: current.refresh_token },
      })).data;
      if (!fresh.access_token) return false;
      window.localStorage.setItem(SESSION_KEY, JSON.stringify({ ...current, ...fresh }));
      window.localStorage.setItem(ACCESS_KEY, fresh.access_token);
      return true;
    } catch {
      return false;
    }
  };
  if (!renewing) {
    const locked: Promise<boolean> = typeof navigator !== "undefined" && navigator.locks
      ? navigator.locks.request("omniassist-session-renewal", renew).then((renewed) => renewed)
      : renew();
    renewing = locked.finally(() => { renewing = null; });
  }
  return renewing;
}

function signOutLocally() {
  window.localStorage.removeItem(SESSION_KEY);
  window.localStorage.removeItem(ACCESS_KEY);
  document.cookie = "omniassist_session=; path=/; max-age=0; samesite=lax";
  // A full page load on purpose: it drops every page's in-memory data from the ended session.
  // eslint-disable-next-line @next/next/no-location-assign-relative-destination
  if (!window.location.pathname.startsWith("/signin")) window.location.assign("/signin");
}

export async function apiRequest<TData>(path: string, init: ApiRequestInit = {}) {
  const send = () => {
    const headers = new Headers(init.headers);
    if (typeof window !== "undefined") {
      const token = window.localStorage.getItem(ACCESS_KEY);
      if (token) headers.set("authorization", `Bearer ${token}`);
    }
    return requestApi<TData>(apiUrl(path), { ...init, headers });
  };
  const refreshUsed = typeof window !== "undefined" ? storedSession()?.refresh_token : undefined;
  try {
    return await send();
  } catch (error) {
    const expired = error instanceof ApiClientError && error.status === 401 && error.code === "UNAUTHENTICATED";
    if (!expired || typeof window === "undefined" || path.startsWith("/auth/") || !refreshUsed) throw error;
    if (await renewSession(refreshUsed)) return send();
    // The refresh token is gone or expired too: the person has to sign in again.
    signOutLocally();
    throw error;
  }
}
