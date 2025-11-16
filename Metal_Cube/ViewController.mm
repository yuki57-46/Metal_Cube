//
//  ViewController.m
//  Metal_Cube
//
//  Created by yuki on 2025/11/16.
//

#import "ViewController.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreVideo/CoreVideo.h>
#import "MetalRenderer.h"

@interface ViewController ()
{
    CAMetalLayer* metalLayer;
    MetalRenderer* renderer;
    CVDisplayLinkRef displayLink;
}
@end


@implementation ViewController

// DisplayLink Callback
static CVReturn DisplayLinkCallback(CVDisplayLinkRef link,
                                    const CVTimeStamp* now,
                                    const CVTimeStamp* outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags* flagsOut,
                                    void* displayLinkContext)
{
    ViewController* vc = (__bridge ViewController*)displayLinkContext;
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc drawFrame];
    });
    return kCVReturnSuccess;
}


- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    // Metal Layer のセットアップ
    
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = NSColor.blackColor.CGColor;
    
    metalLayer = [CAMetalLayer layer];
    metalLayer.device = MTLCreateSystemDefaultDevice();
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.frame = self.view.layer.bounds;
    metalLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    
    [self.view.layer addSublayer:metalLayer];
    
    // C++ Renderer のセットアップ
    renderer = new MetalRenderer(metalLayer);
    renderer->Init();
    
    // DisplayLink のセットアップ
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
    CVDisplayLinkSetOutputCallback(displayLink, &DisplayLinkCallback, (__bridge void*)self);
    CVDisplayLinkStart(displayLink);
    
}

- (void)viewDidLayout {
    [super viewDidLayout];
    
    // レイアウト変更時に Metal Layer のサイズを更新
    metalLayer.frame = self.view.layer.bounds;
    metalLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

// 毎フレーム呼ばれる描画
- (void)drawFrame {
    if (renderer) {
        renderer->DrawFrame();
    }
}

- (void)dealloc {
    if (displayLink) {
        CVDisplayLinkStop(displayLink);
        CVDisplayLinkRelease(displayLink);
    }
    delete renderer;
}

@end
