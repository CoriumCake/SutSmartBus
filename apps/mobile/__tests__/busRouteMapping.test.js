import AsyncStorage from '@react-native-async-storage/async-storage';
import {
    getAllMappings,
    assignRouteToBus,
    getRouteIdForBus,
    assignRouteToMultipleBuses,
    getMappingVersion,
} from '../utils/busRouteMapping';

// Reset the mock store before each test
beforeEach(() => {
    global.__resetMockAsyncStorage();
    jest.clearAllMocks();
});

describe('getAllMappings', () => {
    test('returns empty object when nothing is stored', async () => {
        const result = await getAllMappings();
        expect(result).toEqual({});
    });

    test('returns stored mappings after assignment', async () => {
        await assignRouteToBus('AA:BB:CC:DD:EE:01', 'route_red');
        const result = await getAllMappings();
        expect(result).toEqual({ 'AA:BB:CC:DD:EE:01': 'route_red' });
    });
});

describe('assignRouteToBus', () => {
    test('assigns a route to a bus MAC', async () => {
        const success = await assignRouteToBus('AA:BB:CC:DD:EE:01', 'route_red');
        expect(success).toBe(true);

        const routeId = await getRouteIdForBus('AA:BB:CC:DD:EE:01');
        expect(routeId).toBe('route_red');
    });

    test('removes mapping when routeId is null', async () => {
        await assignRouteToBus('AA:BB:CC:DD:EE:01', 'route_red');
        await assignRouteToBus('AA:BB:CC:DD:EE:01', null);

        const routeId = await getRouteIdForBus('AA:BB:CC:DD:EE:01');
        expect(routeId).toBeNull();
    });

    test('overwrites existing mapping', async () => {
        await assignRouteToBus('AA:BB:CC:DD:EE:01', 'route_red');
        await assignRouteToBus('AA:BB:CC:DD:EE:01', 'route_blue');

        const routeId = await getRouteIdForBus('AA:BB:CC:DD:EE:01');
        expect(routeId).toBe('route_blue');
    });
});

describe('getRouteIdForBus', () => {
    test('returns null for unknown bus MAC', async () => {
        const routeId = await getRouteIdForBus('FF:FF:FF:FF:FF:FF');
        expect(routeId).toBeNull();
    });
});

describe('assignRouteToMultipleBuses', () => {
    test('assigns same route to multiple buses', async () => {
        const macs = ['AA:BB:CC:DD:EE:01', 'AA:BB:CC:DD:EE:02', 'AA:BB:CC:DD:EE:03'];
        const success = await assignRouteToMultipleBuses(macs, 'route_green');
        expect(success).toBe(true);

        for (const mac of macs) {
            const routeId = await getRouteIdForBus(mac);
            expect(routeId).toBe('route_green');
        }
    });

    test('removes mappings when routeId is null', async () => {
        const macs = ['AA:BB:CC:DD:EE:01', 'AA:BB:CC:DD:EE:02'];
        await assignRouteToMultipleBuses(macs, 'route_green');
        await assignRouteToMultipleBuses(macs, null);

        for (const mac of macs) {
            const routeId = await getRouteIdForBus(mac);
            expect(routeId).toBeNull();
        }
    });
});

describe('getMappingVersion', () => {
    test('returns 0 when no version is stored', async () => {
        const version = await getMappingVersion();
        expect(version).toBe(0);
    });
});
