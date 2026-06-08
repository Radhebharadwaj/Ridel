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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, admin-secret, Admin-Secret",
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // GET /api/weather
    if (url.pathname === "/api/weather" && request.method === "GET") {
      const authHeader = request.headers.get("Admin-Secret");
      if (authHeader !== env.ADMIN_SECRET) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), { 
          status: 401, 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }

      const lat = url.searchParams.get("lat");
      const lng = url.searchParams.get("lng");
      if (!lat || !lng) {
        return new Response(JSON.stringify({ error: "Missing lat/lng" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      try {
        const gridLat = Math.round(parseFloat(lat) * 20) / 20;
        const gridLng = Math.round(parseFloat(lng) * 20) / 20;
        const gridId = `grid_${gridLat}_${gridLng}`;

        // Cache Check
        const { results } = await env.DB.prepare("SELECT * FROM weather_grid_cache WHERE grid_id = ?").bind(gridId).all();
        if (results && results.length > 0) {
          const record = results[0];
          const lastUpdated = new Date(record.last_updated);
          const now = new Date();
          const diffMinutes = (now - lastUpdated) / (1000 * 60);

          if (diffMinutes < 60) {
            // Return cached data
            return new Response(JSON.stringify({
              success: true,
              fromCache: true,
              data: {
                temp: record.current_temp,
                condition: record.condition,
                aqi: record.aqi,
                humidity: record.humidity,
                windSpeed: record.wind_speed,
                feelsLike: record.feels_like,
                uvIndex: record.uv_index,
                daily: JSON.parse(record.daily_forecast || "[]")
              }
            }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
          }
        }

        // Fetch & Store
        const weatherUrl = `http://api.weatherapi.com/v1/forecast.json?key=${env.WEATHER_API_KEY}&q=${lat},${lng}&days=7&aqi=yes`;
        const fetchRes = await fetch(weatherUrl);
        const freshData = await fetchRes.json();

        if (freshData.error) {
          throw new Error(freshData.error.message);
        }

        const current = freshData.current;
        const temp = current.temp_c;
        const humidity = current.humidity;
        const windSpeed = current.wind_kph;
        const feelsLike = current.feelslike_c;
        const uvIndex = current.uv;
        const condition = current.condition.code;
        const aqi = current.air_quality ? current.air_quality["us-epa-index"] : 50;
        const daily = freshData.forecast && freshData.forecast.forecastday ? freshData.forecast.forecastday : [];

        await env.DB.prepare(`
          REPLACE INTO weather_grid_cache 
          (grid_id, city_name, current_temp, condition, aqi, last_updated, humidity, wind_speed, feels_like, uv_index, daily_forecast) 
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          gridId, "Unknown", temp, condition, aqi, new Date().toISOString(), humidity, windSpeed, feelsLike, uvIndex, JSON.stringify(daily)
        ).run();

        return new Response(JSON.stringify({
          success: true,
          fromCache: false,
          data: {
            temp,
            condition,
            aqi,
            humidity,
            windSpeed,
            feelsLike,
            uvIndex,
            daily
          }
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
    }

    // POST /admin/broadcast
    if (url.pathname === "/admin/broadcast" && request.method === "POST") {
      // 1. Authenticate with Admin-Secret
      const authHeader = request.headers.get("Admin-Secret");
      if (authHeader !== env.ADMIN_SECRET) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), { 
          status: 401, 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }

      try {
        // 2. Parse incoming payload
        const body = await request.json();
        const { title, body: msgBody, deepLink } = body;

        if (!title || !msgBody) {
          return new Response(JSON.stringify({ error: "Missing title or body" }), { 
            status: 400, 
            headers: { ...corsHeaders, "Content-Type": "application/json" } 
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
            headers: { ...corsHeaders, "Content-Type": "application/json" } 
          });
        }

        // 6. Return Success
        return new Response(JSON.stringify({ success: true, message: "Broadcast sent successfully!" }), { 
          status: 200, 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });

      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), { 
          status: 500, 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }
    }

    return new Response("Not Found", { status: 404, headers: { ...corsHeaders, "Content-Type": "text/plain" } });
  }
};
