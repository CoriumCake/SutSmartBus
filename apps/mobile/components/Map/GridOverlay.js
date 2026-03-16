import React from 'react';
import { View, StyleSheet, Dimensions } from 'react-native';

/**
 * Grid Overlay Component for Visual Alignment in Maps
 * Visualizes screen proportions to help with UI element placement
 */
const GridOverlay = () => {
    const { width, height } = Dimensions.get('window');
    const gridSize = width / 20; // 20 columns = 5% width squares
    const verticalLines = Math.ceil(width / gridSize);
    const horizontalLines = Math.ceil(height / gridSize);

    return (
        <View style={StyleSheet.absoluteFillObject} pointerEvents="none">
            {/* Vertical Lines */}
            {Array.from({ length: verticalLines }).map((_, i) => (
                <View
                    key={`v-${i}`}
                    style={{
                        position: 'absolute',
                        left: i * gridSize,
                        top: 0,
                        bottom: 0,
                        width: 1,
                        backgroundColor: i === 10 ? 'rgba(255,0,0,0.5)' : 'rgba(0,0,0,0.1)', // Center line stronger
                    }}
                />
            ))}

            {/* Horizontal Lines */}
            {Array.from({ length: horizontalLines }).map((_, i) => (
                <View
                    key={`h-${i}`}
                    style={{
                        position: 'absolute',
                        top: i * gridSize,
                        left: 0,
                        right: 0,
                        height: 1,
                        backgroundColor: 'rgba(0,0,0,0.1)',
                    }}
                />
            ))}

            {/* Center Horizontal Line (Screen Center) */}
            <View
                style={{
                    position: 'absolute',
                    top: height / 2,
                    left: 0,
                    right: 0,
                    height: 2,
                    backgroundColor: 'rgba(255,0,0,0.3)',
                }}
            />
        </View>
    );
};

export default GridOverlay;
