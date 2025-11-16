//
//  MetalRenderer.m
//  Metal_Cube
//
//  Created by yuki on 2025/11/16.
//

#import "MetalRenderer.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>
#import <AppKit/AppKit.h>

@interface MetalRendererObjCImpl : NSObject
@property id<MTLDevice> device;
@property id<MTLCommandQueue> queue;
@property CAMetalLayer* layer;

@property id<MTLRenderPipelineState> pipeline;
@property id<MTLBuffer> vertexBuffer;
@property id<MTLBuffer> indexBuffer;
@property id<MTLBuffer> uniformBuffer;
@property int indexCount;

@property id<MTLTexture> depthTexture;
@property id<MTLDepthStencilState> depthState;
@end

@implementation MetalRendererObjCImpl
@end

static simd_float4x4 matrix_perspective_right_hand(float fovYRadians, float aspect, float nearZ, float farZ)
{
    float yScale = 1.0f / tanf(fovYRadians * 0.5f);
    float xScale = yScale / aspect;
    float zRange = farZ - nearZ;
    float zScale = -(farZ + nearZ) / zRange;
    float wz = -(2.0f * farZ * nearZ) / zRange;
    
    return simd_matrix(
       simd_make_float4(xScale, 0,      0, 0),
       simd_make_float4(0,      yScale, 0, 0),
       simd_make_float4(0,      0,      zScale, -1),
       simd_make_float4(0,      0,      wz, 0)
   );
}

static simd_float4x4 matrix_look_at_right_hand(simd_float3 eye, simd_float3 center, simd_float3 up)
{
    simd_float3 z = simd_normalize(eye - center);
    simd_float3 x = simd_normalize(simd_cross(up, z));
    simd_float3 y = simd_cross(z, x);
    
    return simd_matrix(
       simd_make_float4( x.x,  y.x,  z.x, 0),
       simd_make_float4( x.y,  y.y,  z.y, 0),
       simd_make_float4( x.z,  y.z,  z.z, 0),
       simd_make_float4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
       );
}


MetalRenderer::MetalRenderer(CAMetalLayer* layer)
{
    auto obj = [[MetalRendererObjCImpl alloc] init];
    obj.layer = layer;
    impl = (__bridge_retained void*)obj;
}

MetalRenderer::~MetalRenderer()
{
    (__bridge_transfer MetalRendererObjCImpl*)impl;
}

void MetalRenderer::Init()
{
    auto p = (__bridge MetalRendererObjCImpl*)impl;
    p.device = MTLCreateSystemDefaultDevice();
    p.queue = [p.device newCommandQueue];
    
    p.layer.device = p.device;
    p.layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    p.layer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    
    CGSize b = p.layer.bounds.size;
    p.layer.drawableSize = CGSizeMake(b.width * p.layer.contentsScale, b.height * p.layer.contentsScale);
    
    NSError* error = nil;
    id lib = [p.device newDefaultLibrary];
    
    id vfn = [lib newFunctionWithName:@"vs_cube"];
    id ffn = [lib newFunctionWithName:@"fs_cube"];
    
    MTLVertexDescriptor* vdesc = [MTLVertexDescriptor vertexDescriptor];
    vdesc.attributes[0].format = MTLVertexFormatFloat3;
    vdesc.attributes[0].offset = 0;
    vdesc.attributes[0].bufferIndex = 0;
    
    vdesc.attributes[1].format = MTLVertexFormatFloat3;
    vdesc.attributes[1].offset = sizeof(float) * 3;
    vdesc.attributes[1].bufferIndex = 0;
    
    vdesc.layouts[0].stride = sizeof(float) * 6;
    
    MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = vfn;
    desc.fragmentFunction = ffn;
    desc.vertexDescriptor = vdesc;
    desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    desc.colorAttachments[0].pixelFormat = p.layer.pixelFormat;
    
    p.pipeline = [p.device newRenderPipelineStateWithDescriptor:desc error:&error];
    
    MTLDepthStencilDescriptor* ds = [MTLDepthStencilDescriptor new];
    ds.depthCompareFunction = MTLCompareFunctionLess;
    ds.depthWriteEnabled = YES;
    p.depthState = [p.device newDepthStencilStateWithDescriptor:ds];
    
    // Cube vertex data
    float V[] = {
        -0.5f,-0.5f,-0.5f,  1.0f,0.0f,0.0f,
        -0.5f, 0.5f,-0.5f,  0.0f,1.0f,0.0f,
         0.5f, 0.5f,-0.5f,  0.0f,0.0f,1.0f,
         0.5f,-0.5f,-0.5f,  1.0f,1.0f,0.0f,
        
        -0.5f,-0.5f, 0.5f,  1.0f,0.0f,1.0f,
        -0.5f, 0.5f, 0.5f,  0.0f,1.0f,1.0f,
         0.5f, 0.5f, 0.5f,  1.0f,1.0f,1.0f,
         0.5f,-0.5f, 0.5f,  0.0f,0.0f,0.0f,
    };
    
    uint16_t I[] = {
        0,1,2,  0,2,3,
        4,6,5,  4,7,6,
        4,5,1,  4,1,0,
        3,2,6,  3,6,7,
        1,5,6,  1,6,2,
        4,0,3,  4,3,7
    };
    
    p.vertexBuffer = [p.device newBufferWithBytes:V length:sizeof(V) options:0];
    p.indexBuffer = [p.device newBufferWithBytes:I length:sizeof(I) options:0];
    p.indexCount = sizeof(I) / sizeof(uint16_t);
    
    p.uniformBuffer = [p.device newBufferWithLength:sizeof(simd_float4x4) options:0];
    
    // depth texture 作成
    MTLTextureDescriptor* depthDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                        width:p.layer.drawableSize.width
                                                         height:p.layer.drawableSize.height
                                                        mipmapped:NO];
    depthDesc.usage = MTLTextureUsageRenderTarget;
    depthDesc.storageMode = MTLStorageModePrivate;
    
    p.depthTexture = [p.device newTextureWithDescriptor:depthDesc];
    
}

void MetalRenderer::DrawFrame()
{
    auto p = (__bridge MetalRendererObjCImpl*)impl;

    CGSize b = p.layer.bounds.size;
    CGFloat scale = p.layer.contentsScale > 0 ? p.layer.contentsScale : NSScreen.mainScreen.backingScaleFactor;
    CGSize ds = CGSizeMake(b.width * scale, b.height * scale);
    if (!CGSizeEqualToSize(p.layer.drawableSize, ds)) {
        p.layer.drawableSize = ds;
    }
    
    id<CAMetalDrawable> drawable = [p.layer nextDrawable];
    if (!drawable) {
        return;
    }

    
    id<MTLCommandBuffer> cmd = [p.queue commandBuffer];
    auto pass = [MTLRenderPassDescriptor renderPassDescriptor];
    
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);
    
    pass.depthAttachment.texture = p.depthTexture;
    pass.depthAttachment.clearDepth = 1.0;
    pass.depthAttachment.loadAction = MTLLoadActionClear;
    pass.depthAttachment.storeAction = MTLStoreActionDontCare;
    
    id enc = [cmd renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:p.pipeline];
    
    [enc setDepthStencilState:p.depthState];
    
    MTLViewport vp;
    vp.originX = 0;
    vp.originY = 0;
    vp.width = p.layer.drawableSize.width;
    vp.height = p.layer.drawableSize.height;
    vp.znear = 0.0;
    vp.zfar = 1.0;
    [enc setViewport:vp];
    
    // Camera Projection
    float aspect = p.layer.drawableSize.width / p.layer.drawableSize.height;
    float fov = 60.0f * (M_PI / 180.0f);
    float nearZ = 0.1f;
    float farZ = 100.0f;
    
    // Perspective
    simd_float4x4 P = matrix_perspective_right_hand(fov, aspect, nearZ, farZ);
    
    // Camera (View)
    simd_float3 eye = { 0.0f, 0.0f, 3.0f };
    simd_float3 center = { 0.0f, 0.0f, 0.0f };
    simd_float3 up = { 0.0f, 1.0f, 0.0f };
    simd_float4x4 V = matrix_look_at_right_hand(eye, center, up);
    
    // MVP Rotation
    angle += 0.02f;
    float c = cos(angle);
    float s = sin(angle);
    
//    simd_float4x4 rot = {
//        { c, 0, s, 0 },
//        { 0, 1, 0, 0 },
//        { -s,0, c, 0 },
//        { 0, 0, 0, 1 }
//    };
    
    simd_float4x4 M = simd_matrix(
        simd_make_float4( c, 0, s, 0 ),
        simd_make_float4( 0, 1, 0, 0 ),
        simd_make_float4( -s,0, c, 0 ),
        simd_make_float4( 0, 0, 0, 1)
    );
//    simd_float4x4 M = simd_matrix(
//        simd_make_float4( c,-s, 0, 0 ),
//        simd_make_float4( s, c, 0, 0 ),
//        simd_make_float4( 0, 0, 1, 0 ),
//        simd_make_float4( 0, 0, 0, 1)
//    );
//    
//    simd_float4x4 MVP = P * V * M;
    simd_float4x4 MVP = simd_mul(P, simd_mul(V, M));
    
    memcpy(p.uniformBuffer.contents, &MVP, sizeof(MVP));
    
    [enc setVertexBuffer:p.vertexBuffer offset:0 atIndex:0];
    [enc setVertexBuffer:p.uniformBuffer offset:0 atIndex:1];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:p.indexCount indexType:MTLIndexTypeUInt16 indexBuffer:p.indexBuffer indexBufferOffset:0];
    
    [enc endEncoding];
    [cmd presentDrawable:drawable];
    [cmd commit];
}
