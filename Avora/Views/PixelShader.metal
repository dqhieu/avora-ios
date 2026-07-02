#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Snaps each sampled pixel to a `size`-point grid, producing square blocks.
// size <= 1 is a passthrough so the same shader renders the sharp end of the
// pixelate/sharpen animation.
[[ stitchable ]] half4 pixellate(float2 position,
                                 SwiftUI::Layer layer,
                                 float size) {
    if (size <= 1.0) {
        return layer.sample(position);
    }
    float2 snapped = floor(position / size) * size + size * 0.5;
    return layer.sample(snapped);
}
