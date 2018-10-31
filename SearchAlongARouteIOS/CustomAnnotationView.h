#import <UIKit/UIKit.h>
#import <TomTomOnlineSDKMaps/TomTomOnlineSDKMaps.h>

@protocol WayPointAddedDelegate

- (void) setWayPoint:(TTAnnotation* )annotation;

@end

@interface CustomAnnotationView : UIView <TTCalloutView>

@property (nonatomic, strong) TTAnnotation *annotation;
@property (strong, nonatomic) IBOutlet UILabel *poiName;
@property (strong, nonatomic) IBOutlet UILabel *poiAddress;
@property (strong, nonatomic) id myDelegate;
- (IBAction)addWayPoint:(id)sender;

@end
