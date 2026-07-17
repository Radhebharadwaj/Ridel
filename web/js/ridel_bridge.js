/**
 * Ridel HPC Binary Bridge
 * 
 * Zero-copy binary data pipeline for MapLibre route injection.
 * Receives Float64Array buffers from Dart via js_interop and injects
 * GeoJSON directly into MapLibre sources, bypassing JSON serialization.
 */

// Global reference to the MapLibre map instance (set by Dart during onMapCreated)
window.__ridel_mapInstance = null;

/**
 * Captures the MapLibre map instance for direct JS access.
 * Called from Dart via js_interop after onMapCreated fires.
 */
window.__ridel_captureMap = function(mapElementId) {
  try {
    // MapLibre GL JS stores the map instance on the canvas container
    const containers = document.querySelectorAll('.maplibregl-map');
    for (const container of containers) {
      if (container.__maplibre_gl) {
        window.__ridel_mapInstance = container.__maplibre_gl;
        console.log('[RIDEL-HPC] MapLibre instance captured successfully.');
        return true;
      }
    }
    
    // Fallback: try to find via maplibregl internal registry
    if (window.maplibregl && window.maplibregl._maps) {
      const maps = Object.values(window.maplibregl._maps);
      if (maps.length > 0) {
        window.__ridel_mapInstance = maps[0];
        console.log('[RIDEL-HPC] MapLibre instance captured via registry.');
        return true;
      }
    }
    
    console.warn('[RIDEL-HPC] Could not capture MapLibre instance.');
    return false;
  } catch (e) {
    console.error('[RIDEL-HPC] Map capture error:', e);
    return false;
  }
};

/**
 * Sets a GeoJSON route source from a binary Float64Array buffer.
 * Layout: [lng0, lat0, lng1, lat1, lng2, lat2, ...]
 * 
 * @param {Float64Array} coordBuffer - Flat array of [lng, lat] pairs
 * @param {number} pointCount - Number of coordinate pairs
 * @param {string} sourceId - MapLibre source ID to create/update
 * @param {string|null} congestionJson - JSON-encoded congestion array or null
 */
window.__ridel_setRouteFromBuffer = function(coordBuffer, pointCount, sourceId, congestionJson) {
  const map = window.__ridel_mapInstance;
  if (!map) {
    console.warn('[RIDEL-HPC] setRouteFromBuffer called but map not captured.');
    return false;
  }
  
  // Build coordinate array from binary buffer
  const coords = new Array(pointCount);
  for (let i = 0; i < pointCount; i++) {
    coords[i] = [coordBuffer[i * 2], coordBuffer[i * 2 + 1]];
  }
  
  // Build GeoJSON features
  let features;
  if (congestionJson) {
    try {
      const congestion = JSON.parse(congestionJson);
      features = new Array(coords.length - 1);
      for (let i = 0; i < coords.length - 1; i++) {
        const idx = Math.min(
          Math.floor(i / coords.length * congestion.length),
          congestion.length - 1
        );
        features[i] = {
          type: "Feature",
          properties: { index: 0, congestion: congestion[idx] },
          geometry: { type: "LineString", coordinates: [coords[i], coords[i + 1]] }
        };
      }
    } catch (e) {
      console.error('[RIDEL-HPC] Congestion parse error, falling back:', e);
      features = [{
        type: "Feature",
        properties: { index: 0, congestion: "low" },
        geometry: { type: "LineString", coordinates: coords }
      }];
    }
  } else {
    features = [{
      type: "Feature",
      properties: { index: 0, congestion: "low" },
      geometry: { type: "LineString", coordinates: coords }
    }];
  }
  
  const geojson = { type: "FeatureCollection", features: features };
  
  try {
    const source = map.getSource(sourceId);
    if (source) {
      source.setData(geojson);
    } else {
      map.addSource(sourceId, { type: "geojson", data: geojson });
    }
    return true;
  } catch (e) {
    console.error('[RIDEL-HPC] Source injection error for ' + sourceId + ':', e);
    return false;
  }
};

/**
 * Sets a simple LineString route from buffer (no congestion, for alt routes/connectors).
 * 
 * @param {Float64Array} coordBuffer - Flat array of [lng, lat] pairs
 * @param {number} pointCount - Number of coordinate pairs
 * @param {string} sourceId - MapLibre source ID
 * @param {number} routeIndex - Route index for properties
 */
window.__ridel_setSimpleRouteFromBuffer = function(coordBuffer, pointCount, sourceId, routeIndex) {
  const map = window.__ridel_mapInstance;
  if (!map) return false;
  
  const coords = new Array(pointCount);
  for (let i = 0; i < pointCount; i++) {
    coords[i] = [coordBuffer[i * 2], coordBuffer[i * 2 + 1]];
  }
  
  const geojson = {
    type: "FeatureCollection",
    features: [{
      type: "Feature",
      properties: { index: routeIndex },
      geometry: { type: "LineString", coordinates: coords }
    }]
  };
  
  try {
    const source = map.getSource(sourceId);
    if (source) {
      source.setData(geojson);
    } else {
      map.addSource(sourceId, { type: "geojson", data: geojson });
    }
    return true;
  } catch (e) {
    console.error('[RIDEL-HPC] Simple route error for ' + sourceId + ':', e);
    return false;
  }
};

/**
 * Updates the navigation puck GeoJSON from a binary buffer.
 * Much faster than Dart → JSON → JS for high-frequency GPS updates.
 * 
 * @param {number} lng - Longitude
 * @param {number} lat - Latitude
 * @param {number} bearing - Heading in degrees
 */
window.__ridel_updatePuck = function(lng, lat, bearing) {
  const map = window.__ridel_mapInstance;
  if (!map) return;
  
  const source = map.getSource('nav_puck_source');
  if (source) {
    source.setData({
      type: "FeatureCollection",
      features: [{
        type: "Feature",
        properties: { bearing: bearing },
        geometry: { type: "Point", coordinates: [lng, lat] }
      }]
    });
  }
};

console.log('[RIDEL-HPC] Binary Bridge v1.0 loaded.');
