import { getAirQualityStatus } from '../utils/airQuality';

describe('getAirQualityStatus', () => {
    // --- Good range (0-25) ---
    test('returns "Good" for PM2.5 value of 0', () => {
        const result = getAirQualityStatus(0);
        expect(result.status).toBe('Good');
        expect(result.solidColor).toBe('green');
    });

    test('returns "Good" for PM2.5 value of 25', () => {
        const result = getAirQualityStatus(25);
        expect(result.status).toBe('Good');
    });

    // --- Moderate range (26-50) ---
    test('returns "Moderate" for PM2.5 value of 26', () => {
        const result = getAirQualityStatus(26);
        expect(result.status).toBe('Moderate');
    });

    test('returns "Moderate" for PM2.5 value of 50', () => {
        const result = getAirQualityStatus(50);
        expect(result.status).toBe('Moderate');
    });

    // --- Unhealthy for Sensitive range (51-75) ---
    test('returns "Unhealthy (Sensitive)" for PM2.5 value of 51', () => {
        const result = getAirQualityStatus(51);
        expect(result.status).toBe('Unhealthy (Sensitive)');
        expect(result.solidColor).toBe('orange');
    });

    test('returns "Unhealthy (Sensitive)" for PM2.5 value of 75', () => {
        const result = getAirQualityStatus(75);
        expect(result.status).toBe('Unhealthy (Sensitive)');
    });

    // --- Unhealthy range (>75) ---
    test('returns "Unhealthy" for PM2.5 value of 76', () => {
        const result = getAirQualityStatus(76);
        expect(result.status).toBe('Unhealthy');
        expect(result.solidColor).toBe('red');
    });

    test('returns "Unhealthy" for PM2.5 value of 999', () => {
        const result = getAirQualityStatus(999);
        expect(result.status).toBe('Unhealthy');
    });

    // --- Crash prevention: null/undefined ---
    test('returns "No Data" when value is null', () => {
        const result = getAirQualityStatus(null);
        expect(result.status).toBe('No Data');
        expect(result.solidColor).toBe('gray');
    });

    test('returns "No Data" when value is undefined', () => {
        const result = getAirQualityStatus(undefined);
        expect(result.status).toBe('No Data');
    });

    // --- Every result has the expected shape ---
    test('always returns an object with status, color, and solidColor', () => {
        const testValues = [null, undefined, 0, 10, 30, 60, 100];
        testValues.forEach((val) => {
            const result = getAirQualityStatus(val);
            expect(result).toHaveProperty('status');
            expect(result).toHaveProperty('color');
            expect(result).toHaveProperty('solidColor');
        });
    });
});
