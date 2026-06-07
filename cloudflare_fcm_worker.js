/**
 * Cloudflare Worker: FCM HTTP v1 Broadcast REST API
 * 
 * Environment Variables required in Cloudflare Worker Settings:
 * 1. ADMIN_SECRET: Your secret string for authorization.
 * 2. FIREBASE_SERVICE_ACCOUNT: Stringified JSON of your Firebase service account key.
 */

async function getFCMToken(serviceAccountJSON) {
  const account = JSON.parse(serviceAccountJSON);
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now
  };

  const toBase64Url = (obj) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const encodedHeader = toBase64Url(header);
  const encodedClaim = toBase64Url(claim);
  const signatureInput = `${encodedHeader}.${encodedClaim}`;

  // Parse private key from PEM format
  const pem = account.private_key;
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = pem.substring(pemHeader.length, pem.length - pemFooter.length - 1);
  const binaryDerString = atob(pemContents);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }

  // Import Key for Web Crypto API
  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: { name: "SHA-256" } },
    false,
    ["sign"]
  );

  // Sign JWT
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signatureInput)
  );

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${signatureInput}.${encodedSignature}`;

  // Exchange JWT for Bearer Token
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`
  });

  const data = await res.json();
  if (!data.access_token) {
    throw new Error("Failed to generate FCM access token");
  }
  return data.access_token;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // POST /admin/broadcast
    if (url.pathname === "/admin/broadcast" && request.method === "POST") {
      // 1. Authenticate with Admin-Secret
      const authHeader = request.headers.get("Admin-Secret");
      if (authHeader !== env.ADMIN_SECRET) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), { 
          status: 401, 
          headers: { "Content-Type": "application/json" } 
        });
      }

      try {
        // 2. Parse incoming payload
        const body = await request.json();
        const { title, body: msgBody, deepLink } = body;

        if (!title || !msgBody) {
          return new Response(JSON.stringify({ error: "Missing title or body" }), { 
            status: 400, 
            headers: { "Content-Type": "application/json" } 
          });
        }

        // 3. Generate Bearer Token for FCM HTTP v1
        const accessToken = await getFCMToken(env.FIREBASE_SERVICE_ACCOUNT);
        const projectId = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT).project_id;

        // 4. Construct FCM Payload targeting the 'all_users' topic
        const fcmPayload = {
          message: {
            topic: "all_users",
            notification: {
              title: title,
              body: msgBody
            },
            data: {
              type: "external_link", // Helps Flutter app open deep link
              url: deepLink || ""
            }
          }
        };

        // 5. Fire Request to FCM Endpoint
        const fcmResponse = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify(fcmPayload)
        });

        const fcmData = await fcmResponse.json();

        if (!fcmResponse.ok) {
          return new Response(JSON.stringify({ error: fcmData }), { 
            status: fcmResponse.status, 
            headers: { "Content-Type": "application/json" } 
          });
        }

        // 6. Return Success
        return new Response(JSON.stringify({ success: true, message: "Broadcast sent successfully!" }), { 
          status: 200, 
          headers: { "Content-Type": "application/json" } 
        });

      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), { 
          status: 500, 
          headers: { "Content-Type": "application/json" } 
        });
      }
    }

    return new Response("Not Found", { status: 404 });
  }
};
