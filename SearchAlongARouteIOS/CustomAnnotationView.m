#import "CustomAnnotationView.h"

@implementation CustomAnnotationView

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if(self){
        [self createShadow];
    }
    return self;
}

- (void)createShadow {
    self.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.layer.opacity = 1;
    self.layer.shadowOffset = CGSizeMake(2, 2);
    self.layer.shadowOpacity = 1;
}

- (IBAction)addWayPoint:(id)sender {
    [self.myDelegate setWayPoint:self.annotation];
}

@end
