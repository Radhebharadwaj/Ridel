self.onmessage = async function (e) {
  const { requestId, origin, destination, mode, apiKey, waypoints } = e.data;

  try {
    let url = `https://api.olamaps.io/routing/v1/directions?origin=${origin.lat},${origin.lng}&destination=${destination.lat},${destination.lng}&api_key=${apiKey}&mode=${mode}&alternatives=true&steps=true&traffic_metadata=true&overview=full`;

    if (waypoints && waypoints.length > 0) {
      url += `&waypoints=${waypoints.map(w => `${w.lat},${w.lng}`).join('|')}`;
    }

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Accept': 'application/json' }
    });

    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const data = await response.json();
    if (!data.routes || data.routes.length === 0) throw new Error('No routes found');

    const allRoutes = [];
    const allDurations = [];
    let steps = [];
    let distanceKm = 0;
    let durationMins = 0;
    let firstInstruction = 'Head to destination';
    let congestion = null;

    for (let i = 0; i < data.routes.length; i++) {
      const route = data.routes[i];
      const leg = route.legs?.[0];
      if (!leg) continue;

      let polyline = '';
      if (typeof route.overview_polyline === 'string') polyline = route.overview_polyline;
      else if (route.overview_polyline?.points) polyline = route.overview_polyline.points;
      else if (typeof route.geometry === 'string') polyline = route.geometry;

      const coords = decodePolyline(polyline);
      const simplified = douglasPeucker(coords, 0.0001);
      allRoutes.push(simplified);
      allDurations.push(leg.duration || 0);

      if (i === 0) {
        distanceKm = (leg.distance || 0) / 1000;
        durationMins = Math.ceil((leg.duration || 0) / 60);

        const rawSteps = leg.steps || [];
        steps = rawSteps;
        if (rawSteps.length > 0 && rawSteps[0].html_instructions) {
          firstInstruction = rawSteps[0].html_instructions.replace(/<[^>]*>/g, '');
        }

        congestion = extractCongestion(rawSteps);
      }
    }

    if (allRoutes.length === 0) throw new Error('No valid routes parsed');

    // Convert primary route to transferable Float64Array
    const primaryBuffer = new Float64Array(allRoutes[0].length * 2);
    for (let i = 0; i < allRoutes[0].length; i++) {
      primaryBuffer[i * 2] = allRoutes[0][i][1];     // lng
      primaryBuffer[i * 2 + 1] = allRoutes[0][i][0]; // lat
    }

    // Convert alternative routes to transferable Float64Arrays
    const altBuffers = [];
    for (let i = 1; i < allRoutes.length; i++) {
        const altBuffer = new Float64Array(allRoutes[i].length * 2);
        for (let j = 0; j < allRoutes[i].length; j++) {
            altBuffer[j * 2] = allRoutes[i][j][1];     // lng
            altBuffer[j * 2 + 1] = allRoutes[i][j][0]; // lat
        }
        altBuffers.push(altBuffer);
    }
    
    const transferables = [primaryBuffer.buffer, ...altBuffers.map(b => b.buffer)];

    self.postMessage({
      requestId,
      success: true,
      primaryBuffer,
      primaryPointCount: allRoutes[0].length,
      altBuffers: altBuffers,
      altPointCounts: allRoutes.slice(1).map(r => r.length),
      allDurations,
      distanceKm,
      durationMins,
      firstInstruction,
      congestion: congestion ? JSON.stringify(congestion) : null,
      steps: steps ? JSON.stringify(steps) : null
    }, transferables);

  } catch (error) {
    self.postMessage({ requestId, success: false, error: error.message });
  }
};

// Polyline decoder (Google format)
function decodePolyline(encoded) {
  let points = [];
  let index = 0, len = encoded.length;
  let lat = 0, lng = 0;

  while (index < len) {
    let b, shift = 0, result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    let dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    let dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    points.push([lat / 1e5, lng / 1e5]);
  }
  return points;
}

// Douglas-Peucker simplification
function douglasPeucker(points, tolerance) {
  if (points.length <= 2) return points;

  let maxDist = 0;
  let index = 0;

  const end = points.length - 1;

  for (let i = 1; i < end; i++) {
    const dist = perpendicularDistance(points[i], points[0], points[end]);
    if (dist > maxDist) {
      maxDist = dist;
      index = i;
    }
  }

  if (maxDist > tolerance) {
    const recResults1 = douglasPeucker(points.slice(0, index + 1), tolerance);
    const recResults2 = douglasPeucker(points.slice(index, end + 1), tolerance);
    return recResults1.slice(0, recResults1.length - 1).concat(recResults2);
  } else {
    return [points[0], points[end]];
  }
}

function perpendicularDistance(point, lineStart, lineEnd) {
  let x = lineStart[0], y = lineStart[1];
  let dx = lineEnd[0] - x, dy = lineEnd[1] - y;
  
  if (dx !== 0 || dy !== 0) {
    const t = ((point[0] - x) * dx + (point[1] - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      x = lineEnd[0];
      y = lineEnd[1];
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  
  dx = point[0] - x;
  dy = point[1] - y;
  return Math.sqrt(dx * dx + dy * dy);
}

// Extract congestion
function extractCongestion(steps) {
  const congestionList = [];
  let found = false;
  for (let step of steps) {
    let segmentTraffic = "low";
    if (step.travel_advisory && step.travel_advisory.congestion) {
      segmentTraffic = step.travel_advisory.congestion.toString().toLowerCase();
      found = true;
    }
    congestionList.push(segmentTraffic);
  }
  return found ? congestionList : null;
}
