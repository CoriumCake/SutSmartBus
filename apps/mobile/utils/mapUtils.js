/**
 * Map and Geography Utilities for SUT Smart Bus
 */

// Basic degree to radian conversion
export const deg2rad = (deg) => deg * (Math.PI / 180);

/**
 * Calculate distance between two points in meters using Haversine formula
 */
export const getDistanceFromLatLonInM = (lat1, lon1, lat2, lon2) => {
    const R = 6371; // Radius of the earth in km
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const d = R * c; // Distance in km
    return d * 1000; // Distance in m
};

/**
 * Calculate metrics for a route (total distance and segments)
 */
export const getRouteMetrics = (waypoints) => {
    let totalDistance = 0;
    const segmentDistances = [];

    if (!waypoints || waypoints.length < 2) {
        return { totalDistance: 0, segmentDistances: [] };
    }

    for (let i = 0; i < waypoints.length - 1; i++) {
        const d = getDistanceFromLatLonInM(
            waypoints[i].latitude, waypoints[i].longitude,
            waypoints[i + 1].latitude, waypoints[i + 1].longitude
        );
        totalDistance += d;
        segmentDistances.push(d);
    }
    return { totalDistance, segmentDistances };
};

/**
 * Douglas-Peucker polyline simplification algorithm 
 * Reduces points while preserving shape - tolerance in degrees
 */
const perpendicularDistance = (point, lineStart, lineEnd) => {
    const dx = lineEnd.longitude - lineStart.longitude;
    const dy = lineEnd.latitude - lineStart.latitude;
    const mag = Math.sqrt(dx * dx + dy * dy);
    if (mag === 0) return 0;

    const u = ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (mag * mag);
    const closestX = lineStart.longitude + u * dx;
    const closestY = lineStart.latitude + u * dy;

    return Math.sqrt(Math.pow(point.longitude - closestX, 2) + Math.pow(point.latitude - closestY, 2));
};

export const simplifyPolyline = (points, tolerance = 0.00003) => {
    if (!points || points.length < 3) return points;

    let maxDist = 0;
    let maxIdx = 0;

    for (let i = 1; i < points.length - 1; i++) {
        const dist = perpendicularDistance(points[i], points[0], points[points.length - 1]);
        if (dist > maxDist) {
            maxDist = dist;
            maxIdx = i;
        }
    }

    if (maxDist > tolerance) {
        const left = simplifyPolyline(points.slice(0, maxIdx + 1), tolerance);
        const right = simplifyPolyline(points.slice(maxIdx), tolerance);
        return [...left.slice(0, -1), ...right];
    }

    return [points[0], points[points.length - 1]];
};
