export interface Env {
  DB: any;
}

// 🚀 STEP 3: Graph Pre-Computation (Zero runtime string/array filtering)
let globalGraphCache: Map<string, string[]> | null = null;
let globalStopsCache: Map<string, any> | null = null;

// Math constants for Haversine
const R = 6371e3; // Earth radius in meters
const PI_180 = Math.PI / 180;

// Pre-compute basic Haversine (Fast Euclidean approximation for small distances could be used, but standard Haversine is fine if well-typed)
function getHeuristic(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const φ1 = lat1 * PI_180;
  const φ2 = lat2 * PI_180;
  const Δφ = (lat2 - lat1) * PI_180;
  const Δλ = (lon2 - lon1) * PI_180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distanceMeters = R * c;
  
  // Approximate time in seconds (assuming avg bus speed of 5 m/s = 18km/h)
  return distanceMeters / 5.0; 
}

// 🚀 STEP 1: True Binary Min-Heap
class MinHeap {
  private heap: any[] = [];
  
  // Compare by fScore (gScore + heuristic)
  private compare(a: any, b: any) {
    return a.fScore - b.fScore;
  }

  enqueue(node: any) {
    this.heap.push(node);
    this.bubbleUp(this.heap.length - 1);
  }

  dequeue() {
    if (this.heap.length === 1) return this.heap.pop();
    const min = this.heap[0];
    this.heap[0] = this.heap.pop();
    this.sinkDown(0);
    return min;
  }

  isEmpty() {
    return this.heap.length === 0;
  }

  private bubbleUp(index: number) {
    const element = this.heap[index];
    while (index > 0) {
      const parentIndex = Math.floor((index - 1) / 2);
      const parent = this.heap[parentIndex];
      if (this.compare(element, parent) >= 0) break;
      this.heap[index] = parent;
      index = parentIndex;
    }
    this.heap[index] = element;
  }

  private sinkDown(index: number) {
    const length = this.heap.length;
    const element = this.heap[index];
    while (true) {
      let leftChildIndex = 2 * index + 1;
      let rightChildIndex = 2 * index + 2;
      let swap = null;

      if (leftChildIndex < length) {
        let leftChild = this.heap[leftChildIndex];
        if (this.compare(leftChild, element) < 0) {
          swap = leftChildIndex;
        }
      }
      
      if (rightChildIndex < length) {
        let rightChild = this.heap[rightChildIndex];
        if (
          (swap === null && this.compare(rightChild, element) < 0) ||
          (swap !== null && this.compare(rightChild, this.heap[swap]) < 0)
        ) {
          swap = rightChildIndex;
        }
      }

      if (swap === null) break;
      this.heap[index] = this.heap[swap];
      index = swap;
    }
    this.heap[index] = element;
  }
}

export default {
  async fetch(request: Request, env: any, ctx: any): Promise<Response> {
    const url = new URL(request.url);
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, admin-secret",
    };

    // 1. Handle CORS Preflight IMMEDIATELY
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders
      });
    }

    // 🚀 1. COMPREHENSIVE WEATHER ROUTE
    if (url.pathname === '/api/weather' || url.pathname === '/api/weather/') {
      try {
        const lat = url.searchParams.get('lat') || '28.6139'; 
        const lng = url.searchParams.get('lng') || '77.2090';

        // Fetch comprehensive live data from Open-Meteo
        const meteoUrl = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lng}&current=temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m,weather_code&hourly=temperature_2m,weather_code,pm2_5&daily=weather_code,temperature_2m_max,temperature_2m_min,uv_index_max&timezone=auto`;
        
        const response = await fetch(meteoUrl);
        const data = await response.json();

        // Current Data
        const current = data.current;
        const daily = data.daily;
        const hourly = data.hourly;

        // Helper to mock AQI from PM2.5 (Rough estimate for UI purposes)
        const pm25 = hourly?.pm2_5?.[0] ?? 0;
        const aqiVal = pm25 > 0 ? Math.min(Math.round(pm25 * 3), 500) : 120; // Simulated AQI

        // 1. Build Hourly Array (Next 24 hours)
        const hourlyArray = [];
        const currentHourIndex = hourly.time.findIndex((t: string) => new Date(t) >= new Date());
        const startIndex = currentHourIndex > -1 ? currentHourIndex : 0;
        
        for (let i = startIndex; i < startIndex + 24 && i < hourly.time.length; i++) {
          hourlyArray.push({
            time: hourly.time[i],
            temp: Math.round(hourly.temperature_2m[i]),
            code: hourly.weather_code[i]
          });
        }

        // 2. Build Daily Array (7 Days)
        const dailyArray = [];
        for (let i = 0; i < daily.time.length; i++) {
          dailyArray.push({
            date: daily.time[i],
            conditionCode: daily.weather_code[i],
            maxTemp: Math.round(daily.temperature_2m_max[i]),
            minTemp: Math.round(daily.temperature_2m_min[i])
          });
        }

        // 3. Construct the EXACT Schema expected by Flutter
        const flutterResponse = {
          success: true,
          data: {
            temp: Math.round(current.temperature_2m),
            feelsLike: Math.round(current.apparent_temperature),
            weatherCode: current.weather_code, // Use raw WMO code for PremiumWeatherIcon
            condition: current.weather_code.toString(), // Failsafe string
            humidity: current.relative_humidity_2m,
            windSpeed: current.wind_speed_10m,
            uvIndex: daily.uv_index_max?.[0] ?? 0.0,
            tempMax: Math.round(daily.temperature_2m_max[0]),
            tempMin: Math.round(daily.temperature_2m_min[0]),
            aqi: aqiVal,
            hourly: hourlyArray,
            daily: dailyArray
          }
        };

        return new Response(JSON.stringify(flutterResponse), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });

      } catch (err: any) {
        return new Response(JSON.stringify({ success: false, error: err.message }), { 
          status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }
    }

    // 🚀 3. AUTOCOMPLETE ROUTE (FREE NOMINATIM FALLBACK)
    if (url.pathname === '/api/maps/places/v1/autocomplete' || url.pathname === '/api/maps/places/v1/autocomplete/') {
      const input = url.searchParams.get('input');
      
      // If empty search, return empty array instantly
      if (!input || input.length < 3) {
        return new Response(JSON.stringify([]), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      try {
        // Using Nominatim API (Free, No Auth required for basic limits)
        // Scoped to India (countrycodes=in) to make it faster and relevant
        const nominatimUrl = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(input)}&format=json&addressdetails=1&limit=5&countrycodes=in`;
        
        // Nominatim strictly requires a User-Agent header
        const response = await fetch(nominatimUrl, { 
          headers: { "User-Agent": "RidelApp/1.0 (Contact: your_email@domain.com)" } 
        });
        
        const data: any = await response.json();

        // Map OSM data to Ridel's standard schema
        const formattedResults = data.map((item: any) => ({
           name: item.name || item.display_name.split(',')[0],
           address: item.display_name,
           lat: parseFloat(item.lat),
           lng: parseFloat(item.lon)
        }));

        return new Response(JSON.stringify(formattedResults), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        });

      } catch (err: any) {
        // Silently fail and return empty array so UI doesn't crash
        return new Response(JSON.stringify([]), { 
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } 
        });
      }
    }

    try {
      // 2. Loose Path Matching (Fixes trailing slash issues)
      if (url.pathname.includes('/api/bus/route')) {
      const rawStart = url.searchParams.get("start");
      const rawEnd = url.searchParams.get("end");

    if (!rawStart || !rawEnd) {
      return new Response(JSON.stringify({ status: "error", message: "Missing start or end parameters" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let startId = decodeURIComponent(rawStart).replace(/\s+/g, '_');
    let endId = decodeURIComponent(rawEnd).replace(/\s+/g, '_');

    if (!globalGraphCache) {
      console.log("Loading graph from D1 into global memory...");
      globalGraphCache = new Map();
      globalStopsCache = new Map();

      let stopQuery: any = await env.METRO_DB.prepare("SELECT stop_id, stop_name, lat, lon FROM stops").all();
      for (const stop of stopQuery.results) {
        const stopIdStr = stop.stop_id.toString().replace(/\s+/g, '_');
        globalStopsCache!.set(stopIdStr, {
          name: stop.stop_name,
          lat: stop.lat,
          lon: stop.lon,
        });
      }
      stopQuery = null;

      let edgeQuery: any = await env.METRO_DB.prepare("SELECT from_node_id, to_node_id, route_id, time_seconds FROM graph_edges").all();
      for (const row of edgeQuery.results) {
        const fromId = row.from_node_id.toString().replace(/\s+/g, '_');
        const toId = row.to_node_id.toString().replace(/\s+/g, '_');
        
        if (!globalGraphCache!.has(fromId)) globalGraphCache!.set(fromId, []);
        if (!globalGraphCache!.has(toId)) globalGraphCache!.set(toId, []);

        // Store slim strings instead of objects to save RAM
        globalGraphCache!.get(fromId)!.push(`${toId}:${row.route_id}:${row.time_seconds}`);
        globalGraphCache!.get(toId)!.push(`${fromId}:${row.route_id}:${row.time_seconds}`);
      }
      edgeQuery = null;
    }

    console.log("Cache keys sample:", Array.from(globalStopsCache!.keys()).slice(0, 5));
    console.log("Looking up Start ID:", startId);
    console.log(`Looking for Start: ${startId}, End: ${endId}`);

    if (!globalGraphCache!.has(startId) || !globalStopsCache!.has(startId)) {
      return new Response(JSON.stringify({ status: "error", message: "Start node ID not found in graph" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!globalGraphCache!.has(endId) || !globalStopsCache!.has(endId)) {
      return new Response(JSON.stringify({ status: "error", message: "End node ID not found in graph" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const endNode = globalStopsCache!.get(endId);

    // 🚀 STEP 2: Edge-Optimized A*
    const openSet = new MinHeap();
    const gScore = new Map<string, number>();
    const previous = new Map<string, any>();

    gScore.set(startId, 0);
    
    // Heuristic for starting node
    const startNode = globalStopsCache!.get(startId);
    const startH = getHeuristic(startNode.lat, startNode.lon, endNode.lat, endNode.lon);

    openSet.enqueue({ 
      id: startId, 
      gScore: 0, 
      fScore: startH, 
      lastRoute: null, 
      transfers: 0 
    });

    const TRANSFER_PENALTY_SECONDS = 300; 

    while (!openSet.isEmpty()) {
      const current = openSet.dequeue();

      if (current.id === endId) break;

      // Ignore stale heap entries
      if (current.gScore > (gScore.get(current.id) || Infinity)) continue;

      const edges = globalGraphCache!.get(current.id) || [];
      for (let i = 0; i < edges.length; i++) {
        const parts = edges[i].split(':');
        const edgeTo = parts[0];
        const edgeRouteId = parts[1];
        const edgeTimeSeconds = parseFloat(parts[2]);
        
        let newG = current.gScore + edgeTimeSeconds;
        let newTransfers = current.transfers;

        if (current.lastRoute !== null && current.lastRoute !== edgeRouteId) {
          newTransfers += 1;
          newG += TRANSFER_PENALTY_SECONDS;
        }

        if (newG < (gScore.get(edgeTo) || Infinity)) {
          gScore.set(edgeTo, newG);
          previous.set(edgeTo, { 
            from: current.id, 
            edge: { route_id: edgeRouteId }, 
            action: current.lastRoute !== edgeRouteId ? (current.lastRoute === null ? "BOARD" : "TRANSFER") : "RIDE" 
          });
          
          const nextStopData = globalStopsCache!.get(edgeTo);
          const hScore = nextStopData ? getHeuristic(nextStopData.lat, nextStopData.lon, endNode.lat, endNode.lon) : 0;

          openSet.enqueue({ 
            id: edgeTo, 
            gScore: newG, 
            fScore: newG + hScore, 
            lastRoute: edgeRouteId, 
            transfers: newTransfers 
          });
        }
      }
    }

    if (!previous.has(endId)) {
      return new Response(JSON.stringify({ status: "error", message: "No topological path exists between these stops" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Reconstruct path cleanly
    const route_steps = [];
    let curr = endId;
    let totalTransfers = 0;
    let totalTime = gScore.get(endId) || 0;

    // We build it backwards, then reverse
    while (curr !== startId) {
      const stepData = previous.get(curr);
      if (!stepData) break;
      
      const stopInfo = globalStopsCache!.get(curr);
      let action = stepData.action;
      if (curr === endId) action = "ALIGHT";

      if (action === "TRANSFER") totalTransfers++;
      
      route_steps.unshift({
        stop_name: stopInfo.name,
        bus_number: stepData.edge.route_id,
        action: action,
        lat: stopInfo.lat,
        lng: stopInfo.lon
      });

      curr = stepData.from;
    }

    // Add origin
    const originInfo = globalStopsCache!.get(startId);
    const firstStepBus = route_steps.length > 0 ? route_steps[0].bus_number : "Unknown";
    route_steps.unshift({
       stop_name: originInfo.name,
       bus_number: firstStepBus,
       action: "BOARD",
       lat: originInfo.lat,
       lng: originInfo.lon
    });

    const totalStations = route_steps.length;
    let totalFareInr = 10;
    if (totalStations > 2) {
      totalFareInr += Math.floor((totalStations - 2) / 3) * 5;
    }
    if (totalFareInr > 60) totalFareInr = 60;

      return new Response(
        JSON.stringify({
          status: "success",
          total_time_minutes: Math.ceil(totalTime / 60),
          total_transfers: totalTransfers,
          total_fare_inr: totalFareInr,
          route_steps: route_steps
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
      // 3. THE ULTIMATE CATCH-ALL (DO NOT REMOVE)
      return new Response(JSON.stringify({
        status: "error", 
        message: "Worker is ALIVE, but endpoint was not matched.",
        requested_path: url.pathname
      }), { 
        status: 404, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      });
    } catch (error: any) {
      return new Response(
        JSON.stringify({ 
          status: "crash", 
          message: error.message, 
          stack: error.stack 
        }), 
        { 
          status: 500, 
          headers: { ...corsHeaders, "Content-Type": "application/json" } 
        }
      );
    }
  }
};
