import {
    calculateDistance,
    findClosestWaypointIndex,
    findNextStop,
    getStopsFromRoute,
} from '../utils/routeHelpers';

// SUT campus coordinates for realistic test data
const SUT_CENTER = { lat: 14.8818, lon: 102.0177 };
const SUT_GATE = { lat: 14.8785, lon: 102.0210 };

describe('calculateDistance', () => {
    test('distance between same point is 0', () => {
        const d = calculateDistance(SUT_CENTER.lat, SUT_CENTER.lon, SUT_CENTER.lat, SUT_CENTER.lon);
        expect(d).toBe(0);
    });

    test('calculates a positive distance between two different points', () => {
        const d = calculateDistance(SUT_CENTER.lat, SUT_CENTER.lon, SUT_GATE.lat, SUT_GATE.lon);
        expect(d).toBeGreaterThan(0);
    });

    test('distance between SUT center and gate is roughly 300-600m (sanity check)', () => {
        const d = calculateDistance(SUT_CENTER.lat, SUT_CENTER.lon, SUT_GATE.lat, SUT_GATE.lon);
        expect(d).toBeGreaterThan(300);
        expect(d).toBeLessThan(600);
    });

    test('distance is symmetric (A→B === B→A)', () => {
        const d1 = calculateDistance(SUT_CENTER.lat, SUT_CENTER.lon, SUT_GATE.lat, SUT_GATE.lon);
        const d2 = calculateDistance(SUT_GATE.lat, SUT_GATE.lon, SUT_CENTER.lat, SUT_CENTER.lon);
        expect(d1).toBeCloseTo(d2, 5);
    });
});

describe('findClosestWaypointIndex', () => {
    const waypoints = [
        { latitude: 14.8800, longitude: 102.0160 },
        { latitude: 14.8818, longitude: 102.0177 }, // SUT center
        { latitude: 14.8830, longitude: 102.0200 },
    ];

    test('returns the index of the closest waypoint', () => {
        // Point very close to SUT center (index 1)
        const idx = findClosestWaypointIndex(14.8819, 102.0178, waypoints);
        expect(idx).toBe(1);
    });

    test('returns -1 for empty waypoints array', () => {
        const idx = findClosestWaypointIndex(14.8818, 102.0177, []);
        expect(idx).toBe(-1);
    });

    test('returns -1 for null waypoints', () => {
        const idx = findClosestWaypointIndex(14.8818, 102.0177, null);
        expect(idx).toBe(-1);
    });

    test('handles waypoints with lat/lon shorthand', () => {
        const shortWaypoints = [
            { lat: 14.8800, lon: 102.0160 },
            { lat: 14.8818, lon: 102.0177 },
        ];
        const idx = findClosestWaypointIndex(14.8819, 102.0178, shortWaypoints);
        expect(idx).toBe(1);
    });
});

describe('findNextStop', () => {
    const waypoints = [
        { latitude: 14.8800, longitude: 102.0160, isStop: false },
        { latitude: 14.8810, longitude: 102.0170, isStop: true, stopName: 'Library' },
        { latitude: 14.8818, longitude: 102.0177, isStop: false },
        { latitude: 14.8830, longitude: 102.0200, isStop: true, stopName: 'Engineering' },
    ];

    test('returns the next stop ahead of the bus', () => {
        // Bus is near waypoint index 2 → next stop is "Engineering" at index 3
        const result = findNextStop(14.8819, 102.0178, waypoints);
        expect(result).not.toBeNull();
        expect(result.stopName).toBe('Engineering');
        expect(result.distance).toBeGreaterThan(0);
        expect(result.etaMinutes).toBeGreaterThanOrEqual(1);
    });

    test('returns null for empty waypoints', () => {
        expect(findNextStop(14.8818, 102.0177, [])).toBeNull();
    });

    test('returns null for null waypoints', () => {
        expect(findNextStop(14.8818, 102.0177, null)).toBeNull();
    });

    test('returns null when bus coordinates are missing', () => {
        expect(findNextStop(null, null, waypoints)).toBeNull();
    });

    test('wraps around to first stop when no stop ahead', () => {
        // Bus is past the last stop
        const result = findNextStop(14.8835, 102.0210, waypoints);
        // Should wrap to "Library" (first stop)
        if (result) {
            expect(result.stopName).toBe('Library');
            expect(result.distance).toBeNull(); // wrapping route
        }
    });
});

describe('getStopsFromRoute', () => {
    test('filters only waypoints marked as stops', () => {
        const waypoints = [
            { latitude: 14.88, longitude: 102.01, isStop: false },
            { latitude: 14.89, longitude: 102.02, isStop: true, stopName: 'Gate' },
            { latitude: 14.90, longitude: 102.03, isStop: true, stopName: 'Library' },
        ];
        const stops = getStopsFromRoute(waypoints);
        expect(stops).toHaveLength(2);
        expect(stops[0].name).toBe('Gate');
        expect(stops[1].name).toBe('Library');
    });

    test('returns empty array for null waypoints', () => {
        expect(getStopsFromRoute(null)).toEqual([]);
    });

    test('returns empty array when no stops exist', () => {
        const waypoints = [
            { latitude: 14.88, longitude: 102.01, isStop: false },
        ];
        expect(getStopsFromRoute(waypoints)).toEqual([]);
    });

    test('generates fallback name when stopName is missing', () => {
        const waypoints = [
            { latitude: 14.88, longitude: 102.01, isStop: true },
        ];
        const stops = getStopsFromRoute(waypoints);
        expect(stops[0].name).toBe('Stop 1');
    });
});
