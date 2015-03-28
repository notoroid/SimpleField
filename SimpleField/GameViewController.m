//
//  GameViewController.m
//  SimpleField
//
//  Created by 能登 要 on 2015/03/16.
//  Copyright (c) 2015年 Irimasu Densan Planning. All rights reserved.
//

#import "GameViewController.h"

#define CAMERA_RADIUS 10.0
#define AREA_EDGE 1600
#define AREA_EDGE_HALF (AREA_EDGE * 0.5)

static double degreesToRadians(double degrees);
static double degreesToRadians(double degrees) {return degrees * M_PI / 180;}

static double radiansToDegrees(double radians);
static double radiansToDegrees(double radians) {return radians * 180 / M_PI;}

static SCNVector3 vectorNormalize(SCNVector3 v);
static SCNVector3 vectorNormalize(SCNVector3 v)
{
    CGFloat len = sqrt(pow(v.x, 2) + pow(v.y, 2) + pow(v.z, 2));
    return SCNVector3Make(v.x/len, v.y/len, v.z/len);
}

static SCNVector3 vectorSubtract(SCNVector3 a, SCNVector3 b);
static SCNVector3 vectorSubtract(SCNVector3 a, SCNVector3 b)
{
    return SCNVector3Make(a.x-b.x, a.y-b.y, a.z-b.z);
}

// hittojouhou
typedef struct tagHitLine{
    SCNVector3 point1;
    SCNVector3 point2;
    SCNVector3 sub;
    SCNVector3 nor;
    BOOL enterReflect;
}HitLine;

typedef NS_ENUM(NSInteger, TouchEvent )
{
     TouchEventBegan
    ,TouchEventMoved
    ,TouchEventCancelled
    ,TouchEventEnded
};

@interface CameraPan : NSObject
{
    
}
@property(assign,nonatomic) CGPoint startLocation;
@property(assign,nonatomic) CGPoint lastLocation;
@end

@implementation CameraPan


@end


@interface GameViewController () <UIGestureRecognizerDelegate>
{
    __weak SCNNode *_cameraNode;
    __weak SCNNode *_floorNode;
    __weak SCNNode *_cylinderNode;
    SCNVector3 _startRotation;
    
    CGFloat _startLogicalCameraHeight;
    __weak UIPanGestureRecognizer *_singlePanGestureRecognizer;

    CameraPan *_cameraPan;
    CameraPan *_cameraPanForPinch;
    
    // for Pan velocity
    CGFloat _velocityLength;
    SCNVector3 _normalizeVelocity;

    // for velocity
    CFTimeInterval _beginTime;
    CFTimeInterval _totalTime;
    CFTimeInterval _lastTimestamp;
    HitLine _hitLine[4];
    
    CADisplayLink *_displaylink;

    // for camera
    CGFloat _logicalCameraHeight;
}
@end


@implementation GameViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self configureScene];
    [self setupHitLines];
    [self setupNodes];
}

- (void)configureScene
{
    SCNView *scnView = (SCNView *)self.view;
    scnView.backgroundColor = [UIColor grayColor];
    scnView.scene = [SCNScene scene];
    
    SCNCylinder *cylinder       = [SCNCylinder cylinderWithRadius:CAMERA_RADIUS height:50];
    cylinder.radialSegmentCount = 48;
    cylinder.heightSegmentCount = 1;
    SCNNode *cylinderNode       = [SCNNode node];
    cylinderNode.position       = SCNVector3Make(0, 0, 0);
    cylinderNode.rotation       = SCNVector4Make(0, 0, 0, 0);
    cylinderNode.geometry       = cylinder;
    cylinderNode.hidden = YES; // 円筒はkesiteoku
    [scnView.scene.rootNode addChildNode:cylinderNode];
    _cylinderNode = cylinderNode;
    
    _logicalCameraHeight = 800;
    
    SCNNode *cameraNode        = [SCNNode node];
    cameraNode.position        = SCNVector3Make(0, _logicalCameraHeight, 0);
    cameraNode.eulerAngles = SCNVector3Make(degreesToRadians(270) ,0,0);
    cameraNode.camera          = [SCNCamera camera];
    cameraNode.camera.xFov     = 0;
    cameraNode.camera.yFov     = 0;
    cameraNode.camera.zNear    = 10;
    cameraNode.camera.zFar     = 4000;
    cameraNode.camera.aperture = 0.125;
    [_cylinderNode /*scnView.scene.rootNode*/ addChildNode:cameraNode];
        // 円筒の子要素としてカメラを追加する
    _cameraNode = cameraNode;

    [self updateCameraPosition];
        // カメラ位置をhosei
    
    SCNNode *ambientLightNode = [SCNNode node];
    ambientLightNode.light = [SCNLight light];
    ambientLightNode.light.type = SCNLightTypeAmbient;
    ambientLightNode.light.color = [UIColor darkGrayColor];
    [scnView.scene.rootNode addChildNode:ambientLightNode];
    
    SCNNode *spotLightNode = [SCNNode node];
    spotLightNode.light      = [SCNLight light];
    spotLightNode.position   = SCNVector3Make(0, 60, 0);
    spotLightNode.rotation   = SCNVector4Make(-1, 0, 0, 1.571);
    spotLightNode.light.type = SCNLightTypeDirectional;
    [scnView.scene.rootNode addChildNode:spotLightNode];
    
    // 無限床を作成
    SCNFloor *floor            = [SCNFloor floor];
    floor.reflectionFalloffEnd = 50;
    SCNNode *floorNode         = [SCNNode node];
    floorNode.geometry         = floor;
    floorNode.geometry.firstMaterial.diffuse.contents = [UIColor lightGrayColor];
    [scnView.scene.rootNode addChildNode:floorNode];
    _floorNode = floorNode;
    
    // 無限床の上に乗る床を作成
    SCNPlane *plane = [SCNPlane planeWithWidth:AREA_EDGE height:AREA_EDGE];
    SCNNode *planeNode = [SCNNode node];
    planeNode.position = SCNVector3Make(0, 2, 0);
    planeNode.rotation = SCNVector4Make(-1, 0, 0, 1.571);
    planeNode.geometry = plane;
    planeNode.geometry.firstMaterial.diffuse.contents = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    [scnView.scene.rootNode addChildNode:planeNode];
    
    
    [self setupGesture];
}

- (void) setupHitLines
{
    _hitLine[0].point1 = SCNVector3Make( -AREA_EDGE_HALF,  0 ,  AREA_EDGE_HALF);
    _hitLine[0].point2 = SCNVector3Make(  AREA_EDGE_HALF,  0 ,  AREA_EDGE_HALF);
    
    _hitLine[1].point1 = SCNVector3Make(  AREA_EDGE_HALF,  0 ,  AREA_EDGE_HALF);
    _hitLine[1].point2 = SCNVector3Make(  AREA_EDGE_HALF,  0 , -AREA_EDGE_HALF);
    
    _hitLine[2].point1 = SCNVector3Make(  AREA_EDGE_HALF,  0 , -AREA_EDGE_HALF);
    _hitLine[2].point2 = SCNVector3Make( -AREA_EDGE_HALF,  0 , -AREA_EDGE_HALF);
    
    _hitLine[3].point1 = SCNVector3Make( -AREA_EDGE_HALF,  0 , -AREA_EDGE_HALF);
    _hitLine[3].point2 = SCNVector3Make( -AREA_EDGE_HALF,  0 ,  AREA_EDGE_HALF);
    
    
    HitLine *begin = _hitLine;
    HitLine *end = _hitLine + (sizeof(_hitLine) / sizeof(_hitLine[0]));
    for( HitLine *iterator = begin; iterator != end; iterator++ ){
        iterator->enterReflect = NO;
        iterator->sub = vectorNormalize( vectorSubtract( iterator->point2 , iterator->point1 ) );
        // ベクトルを正規化
        iterator->nor = SCNVector3Make( -iterator->sub.z , 0 , iterator->sub.x );
        // 法線ベクトルを作成
    }
}

- (void)setupGesture
{
    // add a tap gesture recognizer
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    panGesture.minimumNumberOfTouches = 1;
    panGesture.maximumNumberOfTouches = 1;
    panGesture.delegate = self;
    panGesture.delaysTouchesBegan = NO;
    panGesture.delaysTouchesEnded = NO;
    _singlePanGestureRecognizer = panGesture;
    
    
    UIRotationGestureRecognizer *rotationGesture = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
    [panGesture requireGestureRecognizerToFail:panGesture];
    rotationGesture.delegate = self;
    rotationGesture.delaysTouchesBegan = NO;
    rotationGesture.delaysTouchesEnded = NO;
    
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    pinchGesture.delegate = self;
    pinchGesture.delaysTouchesBegan = NO;
    pinchGesture.delaysTouchesEnded = NO;
    
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tapGesture.delegate = self;

    NSMutableArray *gestureRecognizers = [NSMutableArray arrayWithArray:@[panGesture,rotationGesture ,pinchGesture ,tapGesture]];

    // Gesturesをマージ
    SCNView *scnView = (SCNView *)self.view;
    [gestureRecognizers addObjectsFromArray:scnView.gestureRecognizers];
    scnView.gestureRecognizers = gestureRecognizers;
}

- (void)setupNodes{
    SCNView *scnView = (SCNView *)self.view;
    
    // グリッドを作成する
    const NSInteger GRID_INTERVAL = (AREA_EDGE) / 16;
    NSInteger begin = -AREA_EDGE_HALF;
    NSInteger end = AREA_EDGE_HALF;
    for (NSInteger x = begin + GRID_INTERVAL;x < end; x+= GRID_INTERVAL) {
        
        for (NSInteger z = begin + GRID_INTERVAL ;z < end; z+= GRID_INTERVAL) {
            SCNCylinder *dot = [SCNCylinder cylinderWithRadius:4 height:0.5];
            SCNNode *planeNode = [SCNNode node];
            planeNode.position = SCNVector3Make(x, 5, z);
            planeNode.rotation = SCNVector4Make(0, 0, 0, 0);
            planeNode.geometry = dot;
            planeNode.geometry.firstMaterial.diffuse.contents = [UIColor lightGrayColor];
            [scnView.scene.rootNode addChildNode:planeNode];
        }
    }
    
    
    SCNBox *box      = [SCNBox boxWithWidth:50 height:100 length:50 chamferRadius:10];
    SCNNode *boxNode = [SCNNode node];
    boxNode.position = SCNVector3Make(50, 50, 0);
    boxNode.geometry = box;
    boxNode.geometry.firstMaterial.diffuse.contents = [UIColor magentaColor];
    [scnView.scene.rootNode addChildNode:boxNode];
    
    /*SCNBox **/box      = [SCNBox boxWithWidth:50 height:160 length:50 chamferRadius:10];
    /*SCNNode **/boxNode = [SCNNode node];
    boxNode.position = SCNVector3Make(0, 80, 50);
    boxNode.geometry = box;
    boxNode.geometry.firstMaterial.diffuse.contents = [UIColor greenColor];
    [scnView.scene.rootNode addChildNode:boxNode];
    
    /*SCNBox **/box      = [SCNBox boxWithWidth:50 height:80 length:50 chamferRadius:10];
    /*SCNNode **/boxNode = [SCNNode node];
    boxNode.position = SCNVector3Make(50, 40, 50);
    boxNode.geometry = box;
    boxNode.geometry.firstMaterial.diffuse.contents = [UIColor orangeColor];
    [scnView.scene.rootNode addChildNode:boxNode];

    /*SCNBox **/box      = [SCNBox boxWithWidth:50 height:80 length:50 chamferRadius:10];
    /*SCNNode **/boxNode = [SCNNode node];
    boxNode.position = SCNVector3Make(50, 40, 100);
    boxNode.geometry = box;
    boxNode.geometry.firstMaterial.diffuse.contents = [UIColor cyanColor];
    [scnView.scene.rootNode addChildNode:boxNode];

}

- (void) cancelScreenDecelerating
{
    [_displaylink removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        // displayLinkを除外
    _displaylink = nil;
}

- (void) updateCameraPosition
{
    CGFloat angleX = _cameraNode.eulerAngles.x;
    // カメラ角度を取得
    
    // 鋭角を求める
    CGFloat acuteAngle = angleX - degreesToRadians(270);
    acuteAngle = ceil(acuteAngle * 1000) / 1000;
    // 鋭角と斜辺から隣辺の長さを求める
    CGFloat cameraHeight = _logicalCameraHeight * cos(acuteAngle);
    CGFloat cameraLength = _logicalCameraHeight * sin(acuteAngle);
    
    SCNVector3 position = _cameraNode.position;
    _cameraNode.position = SCNVector3Make(position.x, cameraHeight, cameraLength);
    // カメラの高さを変更
}

- (void) updateCameraPan:(CameraPan *)cameraPan withTranslation:(CGPoint)translation
{
    // 角度を変更
    const SCNVector3 angles = _cameraNode.eulerAngles;
    CGFloat angleX = radiansToDegrees(angles.x);
    CGFloat signatureUnit = translation.y != 0 ? (translation.y / fabs(translation.y) ) : 1;
    CGFloat translationValue = signatureUnit * MIN(fabs(translation.y), 30);
    
    const CGFloat fact = 0.5;
    translationValue *= fact;
    
    angleX -= translationValue;
    angleX = MIN(315,angleX);
    angleX = MAX(270,angleX);
    
    angleX = degreesToRadians(angleX);
    _cameraNode.eulerAngles = SCNVector3Make(angleX,angles.y,angles.z );
}

- (void) handleRotation:(UIRotationGestureRecognizer *)rotationGestureRecognizer
{
    if( rotationGestureRecognizer.state == UIGestureRecognizerStateBegan ){
        _startRotation = _cylinderNode.eulerAngles;
    }

    _cylinderNode.eulerAngles = SCNVector3Make(_startRotation.x, _startRotation.y + rotationGestureRecognizer.rotation, _startRotation.z);
    
    [self cancelScreenDecelerating];
        // Decelerating をキャンセル
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

- (void) onEvent:(TouchEvent)touchEvent withTouches:(NSSet *)touches withEvent:(UIEvent *)event
{
    if( [touches count] == 1 ){
        if( touchEvent == TouchEventBegan ){
            [self cancelScreenDecelerating];
                // Decelerating をキャンセル
        }
    }else if( [touches count] == 2 ){
        SCNView *scnView = (SCNView *)self.view;
        
        __block CGPoint location = CGPointZero;
        [touches enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            UITouch *touch = obj;
            CGPoint anyLocation = [touch locationInView:scnView];
            location.x += anyLocation.x;
            location.y += anyLocation.y;
        }];
        
        location.x /= touches.count;
        location.y /= touches.count;

        if( touchEvent == TouchEventBegan ){
            if( _cameraPan == nil ){
                _cameraPan = [[CameraPan alloc] init];
                _cameraPan.startLocation = location;
                _cameraPan.lastLocation = _cameraPan.startLocation;
            }
            
        }
        
        if( touchEvent != TouchEventBegan ){
            CGPoint currentLocation = location;
            CGPoint translation = CGPointMake( currentLocation.x - _cameraPan.lastLocation.x, currentLocation.y - _cameraPan.lastLocation.y);
            _cameraPan.lastLocation = currentLocation;
            
            [self updateCameraPan:_cameraPan withTranslation:translation];
                // カメラパンを変更
            
            [self updateCameraPosition];
                // カメラ位置を更新
        }
        
        if( touchEvent == TouchEventEnded || touchEvent == TouchEventCancelled){
            _cameraPan = nil;
        }
        
        [self cancelScreenDecelerating];
            // Decelerating をキャンセル
    }
}

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesBegan: call");
    [self onEvent:TouchEventBegan withTouches:touches withEvent:event];
}

- (void) touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesMoved: call");
    [self onEvent:TouchEventMoved withTouches:touches withEvent:event];
}

- (void) touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesCancelled: call");
    [self onEvent:TouchEventCancelled withTouches:touches withEvent:event];
}

- (void) touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
    NSLog(@"touchesEnded:");
    [self onEvent:TouchEventEnded withTouches:touches withEvent:event];
}

- (void)handleTap:(UITapGestureRecognizer *)tapGestureRecognizer
{
    
}

- (void)handlePan:(UIPanGestureRecognizer *)panGestureRecognizer
{
    // retrieve the SCNView
    SCNView *scnView = (SCNView *)self.view;
    
    if( panGestureRecognizer.numberOfTouches == 1 ){
        [self cancelScreenDecelerating];
            // Decelerating をキャンセル

        CGPoint lastLocation = [panGestureRecognizer locationInView:scnView];
        {
            CGPoint translation = [panGestureRecognizer translationInView:scnView];
            lastLocation.x -= translation.x;
            lastLocation.y -= translation.y;
        }

        __block SCNVector3 startPanLocation = SCNVector3Zero;
        NSArray *hitResults = [scnView hitTest:lastLocation options:nil];
        [hitResults enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            SCNHitTestResult *result = obj;
        
            if( result.node == _floorNode ){
                startPanLocation = result.worldCoordinates;
                *stop = YES;
            }
        }];
        
        CGPoint location = [panGestureRecognizer locationInView:scnView];
        __block SCNVector3 endPanLocation = SCNVector3Zero;
        /*NSArray **/hitResults = [scnView hitTest:location options:nil];
        [hitResults enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            SCNHitTestResult *result = obj;
            
            if( result.node == _floorNode ){
                endPanLocation = result.worldCoordinates;
                SCNVector3 translation = SCNVector3Make( startPanLocation.x - endPanLocation.x
                                                        ,startPanLocation.y - endPanLocation.y
                                                        ,startPanLocation.z - endPanLocation.z);
                SCNVector3 position = _cylinderNode.position /*_cameraNode.position*/;
                position.x += translation.x;
                position.z += translation.z;
                
                // 衝突判定を作成
                position.x = MAX(-AREA_EDGE_HALF + CAMERA_RADIUS,position.x);
                position.x = MIN( AREA_EDGE_HALF - CAMERA_RADIUS,position.x);
                position.z = MAX(-AREA_EDGE_HALF + CAMERA_RADIUS,position.z);
                position.z = MIN( AREA_EDGE_HALF - CAMERA_RADIUS,position.z);
                
                _cylinderNode.position = position;
                
                *stop = YES;
            }
        }];
        
        [panGestureRecognizer setTranslation:CGPointZero inView:scnView];
            // ドラッグ位置をリセットする

        CGPoint velocity = [panGestureRecognizer velocityInView:scnView];
        
        CGPoint afterLocation = [panGestureRecognizer locationInView:scnView];
        const CGFloat fact = .25;
        afterLocation.x += (velocity.x * fact);
        afterLocation.y += (velocity.y * fact);
        
        __block SCNVector3 velocityLocation = SCNVector3Zero;
        /*NSArray **/hitResults = [scnView hitTest:afterLocation options:nil];
        __block BOOL hiiTest = NO;
        [hitResults enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            SCNHitTestResult *result = obj;
            if( result.node == _floorNode ){
                velocityLocation = result.worldCoordinates;
                
                hiiTest = YES;
                    //　ヒット確認
                
                *stop = YES;
            }
        }];
        
        if( panGestureRecognizer.state == UIGestureRecognizerStateChanged && hiiTest ){
            CGFloat baseLength = sqrt( pow(endPanLocation.x - velocityLocation.x,2) + pow(endPanLocation.z - velocityLocation.z ,2) );
                // 長さを計算
            
            // ベクトルを正規化
            SCNVector3 normalize = vectorNormalize(velocityLocation);
            _normalizeVelocity = normalize;
            
            CGFloat fact = 1.0;
            _velocityLength = baseLength * fact;
            _velocityLength = MIN(600 /*最大加速値*/,_velocityLength );
            
            _beginTime = CACurrentMediaTime();
            _totalTime = 2.0f /*この値はベクトルの長さを反映すること*/;
            _lastTimestamp = CACurrentMediaTime();
            
            // hitlineを初期化
            HitLine *begin = _hitLine;
            HitLine *end = _hitLine + (sizeof(_hitLine) / sizeof(_hitLine[0]));
            for( HitLine *iterator = begin; iterator != end; iterator++ ){
                iterator->enterReflect = NO;
            }
            
            CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDecelerating:)];
            [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
            _displaylink = link;
        }
    }
}

- (void)handleDecelerating:(CADisplayLink *)link
{
    //    NSLog(@"handleDecelerating call");
    
    CGFloat ratio = ([link timestamp] - _beginTime) / _totalTime;
    if (ratio >= 1.0) {
        [self cancelScreenDecelerating];
    }else{
        CGFloat delta = [link timestamp] - _lastTimestamp;
        _lastTimestamp = [link timestamp];
        
        if( _singlePanGestureRecognizer.state == UIGestureRecognizerStatePossible ){
            
            SCNVector3 position = _cylinderNode.position;
            
            HitLine *begin = _hitLine;
            HitLine *end = _hitLine + (sizeof(_hitLine) / sizeof(_hitLine[0]));
            for( HitLine *iterator = begin; iterator != end; iterator++ ){
                SCNVector3 point1Position = iterator->point1;
                SCNVector3 point2Position = iterator->point2;
                SCNVector3 nor = iterator->nor /*SCNVector3Make( -sub.z , 0 , sub.x )*/;
                    // 法線ベクトルを作成

                // 玉から面と垂直な線を出して面と交差するか調べる
                CGFloat sx = -nor.x * CAMERA_RADIUS;
                CGFloat sz = -nor.z * CAMERA_RADIUS;
                CGFloat d = - (point1Position.x * nor.x + point1Position.z * nor.z); // 内積
                CGFloat t = - (nor.x * position.x + nor.z * position.z + d) / (nor.x * sx + nor.z * sz); //
                
                if( t > 0 && t <= 1){
                    // 交点が線分の中に入っているか確認
                    CGFloat cx = position.x + t * sx;
                    CGFloat cz = position.z + t * sz;
                    CGFloat acx = cx - point1Position.x;
                    CGFloat acz = cz - point1Position.z;
                    
                    CGFloat bcx = cx - point2Position.x;
                    CGFloat bcz = cz - point2Position.z;
                    
                    // 線分の中に含まれる
                    if( (acx * bcx) + (acz * bcz) <= 0){
                        if( iterator->enterReflect != YES ){
                            iterator->enterReflect = YES;
                                // 反射状態に入る
                            
                            // 反射ベクトル
                            double d = (nor.x * _normalizeVelocity.x + nor.z * _normalizeVelocity.z) * 2.0;
                            SCNVector3 normalizeVelocity = SCNVector3Make( _normalizeVelocity.x - d * nor.x
                                                                          ,_normalizeVelocity.y
                                                                          ,_normalizeVelocity.z - d * nor.z );
                            
                            _normalizeVelocity = normalizeVelocity;
                        }
                        continue;
                    }else{
                        iterator->enterReflect = NO;
                            // 反射状態から抜ける
                    }
                }else{
                    iterator->enterReflect = NO;
                        // 反射状態から抜ける
                }
                
                // 円が始点と重なっているか確認
                CGFloat vx = position.x - point1Position.x;
                CGFloat vz = position.z - point1Position.z;
                if(vx * vx + vz * vz < CAMERA_RADIUS * CAMERA_RADIUS){
                    if( iterator->enterReflect != YES ){
                        iterator->enterReflect = YES;
                        
                        CGFloat length = sqrt((vx * vx) + (vz * vz));
                        if(length > 0){
                            length = 1 / length;
                        }
                        vx = vx * length;
                        vz = vz * length;
                        
                        // 反射ベクトル
                        double d = (nor.x * _normalizeVelocity.x + nor.z * _normalizeVelocity.z) * 2.0;
                        SCNVector3 normalizeVelocity = SCNVector3Make( _normalizeVelocity.x - d * nor.x
                                                                      ,_normalizeVelocity.y
                                                                      ,_normalizeVelocity.z - d * nor.z );
                        
                        _normalizeVelocity = normalizeVelocity;
                        
                    }
                    continue;
                }else{
                    iterator->enterReflect = NO;
                }
                
                // 円が始点と重なっているか確認
                /*CGFloat*/ vx = position.x - point2Position.x;
                /*CGFloat*/ vz = position.z - point2Position.z;
                if(vx * vx + vz * vz < CAMERA_RADIUS * CAMERA_RADIUS){
                    if( iterator->enterReflect != YES ){
                        iterator->enterReflect = YES;
                        
                        CGFloat length = sqrt((vx * vx) + (vz * vz));
                        if(length > 0){
                            length = 1 / length;
                        }
                        vx = vx * length;
                        vz = vz * length;
                        
                        // 反射ベクトル
                        double d = (nor.x * _normalizeVelocity.x + nor.z * _normalizeVelocity.z) * 2.0;
                        SCNVector3 normalizeVelocity = SCNVector3Make( _normalizeVelocity.x - d * nor.x
                                                                      ,_normalizeVelocity.y
                                                                      ,_normalizeVelocity.z - d * nor.z );
                        
                        _normalizeVelocity = normalizeVelocity;
                    }
                    continue;
                }else{
                    iterator->enterReflect = NO;
                }
            }
            
            position.x -= (_normalizeVelocity.x * _velocityLength * delta);
            position.z -= (_normalizeVelocity.z * _velocityLength * delta);
            
            _cylinderNode.position = position;
        }
        
        const CGFloat fact = 1.4/*摩擦係数*/;
        _velocityLength -= ((_velocityLength * delta) * fact );
        _velocityLength = MAX(0,_velocityLength);
        if( _velocityLength < 0.05 ){
            _velocityLength = 0;
        }
        
    }
}

- (void) handlePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer
{
    if( pinchGestureRecognizer.state == UIGestureRecognizerStateBegan ){
        _startLogicalCameraHeight = _logicalCameraHeight;
    }

    if( pinchGestureRecognizer.state != UIGestureRecognizerStateEnded ){
        CGFloat logicalCameraHeight = _startLogicalCameraHeight;
        logicalCameraHeight = logicalCameraHeight + (600 - pinchGestureRecognizer.scale * 600);
        
        if( pinchGestureRecognizer.state != UIGestureRecognizerStateBegan ){
            logicalCameraHeight = MAX(200,logicalCameraHeight);
            logicalCameraHeight = MIN(800,logicalCameraHeight);
        }
        _logicalCameraHeight = logicalCameraHeight;
        
        
        [self updateCameraPosition];
             // カメラポジションの更新
    }
    
    SCNView *scnView = (SCNView *)self.view;
    if( pinchGestureRecognizer.state == UIGestureRecognizerStateBegan ){
        if( _cameraPanForPinch == nil ){
            _cameraPanForPinch = [[CameraPan alloc] init];
            _cameraPanForPinch.startLocation = [pinchGestureRecognizer locationInView:scnView];
            _cameraPanForPinch.lastLocation = _cameraPanForPinch.startLocation;
        }
    }
    
    if( pinchGestureRecognizer.state != UIGestureRecognizerStateBegan ){
        //    NSLog(@"pinchGestureRecognizer.state=%@",@(pinchGestureRecognizer.state));
        CGPoint currentLocation = [pinchGestureRecognizer locationInView:scnView];
        CGPoint translation = CGPointMake( currentLocation.x - _cameraPanForPinch.lastLocation.x, currentLocation.y - _cameraPanForPinch.lastLocation.y);
        _cameraPanForPinch.lastLocation = currentLocation;
            // 位置を記憶
        
        
        [self updateCameraPan:_cameraPanForPinch withTranslation:translation];
        // カメラパンを変更
        
        [self updateCameraPosition];
        // カメラ位置を更新
    }
    
    if( pinchGestureRecognizer.state == UIGestureRecognizerStateEnded || pinchGestureRecognizer.state == UIGestureRecognizerStateCancelled || pinchGestureRecognizer.state == UIGestureRecognizerStateFailed){
        _cameraPanForPinch = nil;
    }
    
    [self cancelScreenDecelerating];
        // Decelerating をキャンセル
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    } else {
        return UIInterfaceOrientationMaskAll;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end
