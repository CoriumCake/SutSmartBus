// Jest setup file for SUT Smart Bus mobile app

// Mock AsyncStorage with in-memory store
let mockStore = {};
jest.mock('@react-native-async-storage/async-storage', () => ({
    getItem: jest.fn((key) => Promise.resolve(mockStore[key] || null)),
    setItem: jest.fn((key, value) => {
        mockStore[key] = value;
        return Promise.resolve();
    }),
    removeItem: jest.fn((key) => {
        delete mockStore[key];
        return Promise.resolve();
    }),
    clear: jest.fn(() => {
        mockStore = {};
        return Promise.resolve();
    }),
}));

// Expose a way to reset the mock store between tests
global.__resetMockAsyncStorage = () => {
    mockStore = {};
};

// Mock react-native-maps
jest.mock('react-native-maps', () => {
    const React = require('react');
    const { View } = require('react-native');
    const MockMapView = React.forwardRef((props, ref) =>
        React.createElement(View, { ...props, ref })
    );
    MockMapView.Marker = (props) => React.createElement(View, props);
    MockMapView.Polyline = (props) => React.createElement(View, props);
    MockMapView.Circle = (props) => React.createElement(View, props);
    return {
        __esModule: true,
        default: MockMapView,
        Marker: MockMapView.Marker,
        Polyline: MockMapView.Polyline,
        Circle: MockMapView.Circle,
    };
});

// Mock expo-location
jest.mock('expo-location', () => ({
    requestForegroundPermissionsAsync: jest.fn(() =>
        Promise.resolve({ status: 'granted' })
    ),
    getCurrentPositionAsync: jest.fn(() =>
        Promise.resolve({
            coords: { latitude: 14.8818, longitude: 102.0177 },
        })
    ),
    watchPositionAsync: jest.fn(),
}));

// Silence noisy logs during tests
jest.spyOn(console, 'log').mockImplementation(() => { });
jest.spyOn(console, 'warn').mockImplementation(() => { });
