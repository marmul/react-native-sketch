//
//  RNSketch.m
//  RNSketch
//
//  Created by Jeremy Grancher on 28/04/2016.
//  Copyright © 2016 Jeremy Grancher. All rights reserved.
//
//  Modified for multi touch by Martin Müller on 01/09/2016.
//  Modifications Copyright © 2016 Martin Müller. All rights reserved.
//

#import "RNSketch.h"
#import "RNSketchManager.h"
#import "RCTEventDispatcher.h"
#import "RCTView.h"
#import "UIView+React.h"

@interface PathCreator : NSObject

@property bool needsDraw;
@property UIBezierPath* _path;

-(instancetype)init;
-(void)beginPoint:(CGPoint)point;
-(void)addPoint:(CGPoint)point;
-(void)clear;
-(void)finish;
-(void)stroke;
-(void)setOffest:(CGPoint)point;
-(CGPoint)lastPoint;

@end

@implementation PathCreator
{
  //UIBezierPath *_path;
  CGPoint _points[5];
  uint _counter;
  CGPoint _offset;
}

-(instancetype)init{
  self = [super init];
  self._path = [UIBezierPath bezierPath];
  _counter = 0;
  _offset = CGPointMake(0,0);
  return self;
}

-(void)beginPoint:(CGPoint)point {
  _points[0] = CGPointMake(point.x + _offset.x, point.y + _offset.y );
  _counter = 1;
}

-(void)addPoint:(CGPoint)point {
  _points[_counter] = CGPointMake(point.x + _offset.x, point.y + _offset.y );
  _counter++;
  if (_counter >=5) [self finish];
}

-(void)clear {
  _counter = 0;
  self.needsDraw = false;
  [self._path removeAllPoints];
}

-(void)finish {
  // Move the endpoint to the middle of the line
  _points[3] = CGPointMake((_points[2].x + _points[4].x) / 2, (_points[2].y + _points[4].y) / 2);
  
  [self._path moveToPoint:_points[0]];
  [self._path addCurveToPoint:_points[3] controlPoint1:_points[1] controlPoint2:_points[2]];
  
  self.needsDraw = true;
  
  // Replace points and get ready to handle the next segment
  _points[0] = _points[3];
  _points[1] = _points[4];
  _counter = 2;
}

-(void)stroke {
  [self._path stroke];
}

-(void)setOffest:(CGPoint)point {
  _offset = point;
}

-(CGPoint)lastPoint {
  if (_counter>0) return _points[_counter - 1];
  else return CGPointMake(0,0); //just returning some default
}

@end

//Quick UIColor creation for debugging:
#define UIColorFromRGB(rgbValue) \
[UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
green:((float)((rgbValue & 0x00FF00) >>  8))/255.0 \
blue:((float)((rgbValue & 0x0000FF) >>  0))/255.0 \
alpha:1.0]


@implementation RNSketch
{
  // Internal
  RCTEventDispatcher *_eventDispatcher;
  UIButton *_clearButton;
  UIImage *_image;
  
  NSMutableDictionary* _pathCreatorForTouch;
  
  // Configuration settings
  UIColor *_fillColor;
  UIColor *_strokeColor;
  int _strokeThickness;
}

#pragma mark - UIViewHierarchy methods


- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
  if ((self = [super init])) {
    // Internal setup
    self.multipleTouchEnabled = YES;
    _eventDispatcher = eventDispatcher;
    _pathCreatorForTouch = [[NSMutableDictionary alloc] init];
    
    // TODO: Find a way to get an functionnal external 'clear button'
    [self initClearButton];
  }

  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [self drawBitmap];
}


#pragma mark - Subviews


- (void)initClearButton
{
  // Clear button
  CGRect frame = CGRectMake(0, 0, 40, 40);
  _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _clearButton.frame = frame;
  _clearButton.enabled = false;
  _clearButton.tintColor = [UIColor blackColor];
  _clearButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
  [_clearButton setTitle:@"x" forState:UIControlStateNormal];
  [_clearButton addTarget:self action:@selector(clearDrawing) forControlEvents:UIControlEventTouchUpInside];

  // Clear button background
  UIButton *background = [UIButton buttonWithType:UIButtonTypeCustom];
  background.frame = frame;

  // Add subviews
  [self addSubview:background];
  [self addSubview:_clearButton];
}


#pragma mark - UIResponder methods


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [self beginPathCreatorForTouches: touches];
}

- (void)beginPathCreatorForTouches:(NSSet *)touches {
  if ([touches count] > 0) {
    for (UITouch *touch in touches) {
      NSValue *key = [NSValue value:&touch withObjCType:@encode(void *)];
      PathCreator *pc = [[PathCreator alloc] init];
      pc._path.lineWidth = _strokeThickness;
      [_pathCreatorForTouch setObject:pc forKey:key];
      
      [pc beginPoint: [touch locationInView:self]];
    }
  }
}

- (void)movePathCreatorForTouches:(NSSet *)touches {
  if ([touches count] > 0) {
    for (UITouch *touch in touches) {
      NSValue *key = [NSValue value:&touch withObjCType:@encode(void *)];

      PathCreator *pc = [_pathCreatorForTouch objectForKey:key];
      
      [pc addPoint: [touch locationInView:self]];
      if ([pc needsDraw]) [self setNeedsDisplay];
    }
  }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [self movePathCreatorForTouches: touches];
}

- (void)removePathCreatorForTouches:(NSSet *)touches {
  if ([touches count] > 0) {
    for (UITouch *touch in touches) {
      NSValue *key = [NSValue value:&touch withObjCType:@encode(void *)];
      PathCreator *pc = [_pathCreatorForTouch objectForKey:key];
      [pc clear];
      [_pathCreatorForTouch removeObjectForKey:key];
      //no deallocation here due to ARC
    }
  }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  // Enabling to clear
  [_clearButton setEnabled:true];

  [self drawBitmap];
  [self setNeedsDisplay];
  
  [self removePathCreatorForTouches: touches];
  
  // Send event
  NSDictionary *bodyEvent = @{
                              @"target": self.reactTag,
                              @"image": [self drawingToString],
                              };
  [_eventDispatcher sendInputEventWithName:@"topChange" body:bodyEvent];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [self touchesEnded:touches withEvent:event];
}


#pragma mark - UIViewRendering methods


- (void)drawRect:(CGRect)rect
{
  [_image drawInRect:rect];
  [_strokeColor setStroke];
  for(id key in _pathCreatorForTouch) {
    id pc = [_pathCreatorForTouch objectForKey:key];
    [pc stroke];
    //[UIColorFromRGB(0xFF0000) setStroke]; //for debug: switch color to red for remaining touches
  }
}


#pragma mark - Drawing methods

- (void)drawBitmap
{
  UIGraphicsBeginImageContextWithOptions(self.bounds.size, YES, 0);

  // If first time, paint background
  if (!_image) {
    [_fillColor setFill];
    [[UIBezierPath bezierPathWithRect:self.bounds] fill];
  }

  // Draw with context
  [_image drawAtPoint:CGPointZero];
  [_strokeColor setStroke];
  for(id key in _pathCreatorForTouch) {
    id pc = [_pathCreatorForTouch objectForKey:key];
    [pc stroke];
    //[UIColorFromRGB(0xFF0000) setStroke]; //for debug: switch color to red for remaining touches
  }
  
  _image = UIGraphicsGetImageFromCurrentImageContext();

  UIGraphicsEndImageContext();
}


#pragma mark - Export drawing


- (NSString *)drawingToString
{
  return [UIImageJPEGRepresentation(_image, 1) base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
}


#pragma mark - Clear drawing


- (void)clearDrawing
{
  // Disabling to clear
  [_clearButton setEnabled:false];

  _image = nil;

  [self drawBitmap];
  [self setNeedsDisplay];

  // Send event
  NSDictionary *bodyEvent = @{
                              @"target": self.reactTag,
                              };
  [_eventDispatcher sendInputEventWithName:@"onReset" body:bodyEvent];
}


#pragma mark - Setters


- (void)setFillColor:(UIColor *)fillColor
{
  _fillColor = fillColor;
}

- (void)setStrokeColor:(UIColor *)strokeColor
{
  _strokeColor = strokeColor;
}

- (void)setStrokeThickness:(NSInteger)strokeThickness
{
  _strokeThickness = strokeThickness;
}

@end
