#import "ViewController.h"
#import "CustomAnnotationView.h"

#import <TomTomOnlineSDKSearch/TomTomOnlineSDKSearch.h>
#import <TomTomOnlineSDKRouting/TomTomOnlineSDKRouting.h>
#import <TomTomOnlineSDKMapsUIExtensions/TomTomOnlineSDKMapsUIExtensions.h>

static const int BOTTOM_CONSTRAINT_CENTER_BUTTON_CONSTANT = -20;
static const int LEFT_CONSTRAINT_CENTER_BUTTON_OFFSET = 57;
static const int SEARCH_MAX_DETOUR_TIME = 1000;
static const int SEARCH_RESULTS_LIMIT = 10;
static const int MESSAGE_DISPLAY_TIME_IN_SECONDS = 3;
static const int KEYBOARD_SHOW_MULTIPLIER = 1;
static const int KEYBOARD_HIDE_MULTIPLIER = -1;
static NSString *const EMPTY_DEPARTURE_POSITION_TAG = @" ";

@interface ViewController () <TTMapViewDelegate, TTAnnotationDelegate, TTAlongRouteSearchDelegate, WayPointAddedDelegate, UISearchBarDelegate>
@property(weak, nonatomic) IBOutlet UIButton *gasStationButton;
@property(weak, nonatomic) IBOutlet UIButton *restaurantButton;
@property(weak, nonatomic) IBOutlet UIButton *cashMachineButton;
@property(weak, nonatomic) IBOutlet UIButton *clearMapButton;
@property(weak, nonatomic) IBOutlet TTMapView *tomtomMap;
@property(weak, nonatomic) IBOutlet UISearchBar *searchBar;
@property(weak, nonatomic) IBOutlet NSLayoutConstraint *bottomConstraint;
@property(weak, nonatomic) IBOutlet NSLayoutConstraint *bottomStackHeight;
@property(weak, nonatomic) IBOutlet TTControlView *controlView;

@property CLLocationCoordinate2D departurePosition;
@property CLLocationCoordinate2D destinationPosition;
@property CLLocationCoordinate2D wayPointPosition;
@property TTAnnotationImage * departureImage;
@property NSMutableDictionary *positionsPoisInfo;
@property TTFullRoute *fullRoute;
@property Boolean keyboardShown;
@property NSArray *searchButtons;
@property UIAlertController *progressDialog;

@property(strong, nonatomic) TTRoute *route;
@property(strong, nonatomic) TTReverseGeocoder *reverseGeocoder;
@property(strong, nonatomic) TTAlongRouteSearch *alongRouteSearch;

- (void)setWayPoint:(TTAnnotation *)annotation;

- (void)createAndDisplayMarkerAtPosition:(CLLocationCoordinate2D)coords withAnnotationImage:(TTAnnotationImage *)image andBalloonText:(NSString *)text;

- (void)clearMap;

- (void)drawRouteWithDeparture:(CLLocationCoordinate2D)departure andDestination:(CLLocationCoordinate2D)destination;

- (void)drawRouteWithDeparture:(CLLocationCoordinate2D)departure andDestination:(CLLocationCoordinate2D)destination andWayPoint:(CLLocationCoordinate2D)wayPoint;

- (NSString *)coordinatesToString:(CLLocationCoordinate2D)coords;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initTomTomServices];
    [self initUIViews];
    [self initKeyboardNotificationEvents];
    [self initProgressDialog];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator {
    [self updateMapCenterButtonPosition:size];
}

- (void)initTomTomServices {
    self.tomtomMap.delegate = self;
    self.tomtomMap.annotationManager.delegate = self;
    self.controlView.mapView = self.tomtomMap;
    self.reverseGeocoder = [[TTReverseGeocoder alloc] init];
    self.route = [[TTRoute alloc] init];
    self.alongRouteSearch = [[TTAlongRouteSearch alloc] init];
    self.alongRouteSearch.delegate = self;
    
    self.departurePosition = kCLLocationCoordinate2DInvalid;
    self.destinationPosition = kCLLocationCoordinate2DInvalid;
    self.wayPointPosition = kCLLocationCoordinate2DInvalid;
    
    [self.controlView initDefaultCenterButton];
    [self updateMapCenterButtonPosition:self.view.frame.size];
}

- (void)updateMapCenterButtonPosition:(CGSize)size {
    self.controlView.bottomLayoutConstraintCenterButton.constant = BOTTOM_CONSTRAINT_CENTER_BUTTON_CONSTANT;
    self.controlView.leftLayoutConstraintCenterButton.constant = size.width - LEFT_CONSTRAINT_CENTER_BUTTON_OFFSET;
}

- (void)initUIViews {
    self.searchBar.delegate = self;
    self.departureImage = [TTAnnotationImage createPNGWithName:@"ic_map_route_departure"];
    self.positionsPoisInfo = [[NSMutableDictionary alloc] init];
    self.searchButtons = @[self.gasStationButton, self.restaurantButton, self.cashMachineButton];
}

- (void)initKeyboardNotificationEvents {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
}

- (void)initProgressDialog {
    UIStoryboard *mainBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    self.progressDialog = [mainBoard instantiateViewControllerWithIdentifier:@"progressDialog"];
    self.progressDialog.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    self.progressDialog.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
}

- (void)showDialogInProgress {
    if (![self presentedViewController]) {
        [self presentViewController:self.progressDialog animated:YES completion:nil];
    }
}

- (void)dismissDialogInProgress {
    if ([self presentedViewController] == self.progressDialog) {
        [self.progressDialog dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)search:(TTAlongRouteSearch *)search completedWithResponse:(TTAlongRouteSearchResponse *)response {
    [self.tomtomMap.annotationManager removeAllAnnotations];
    [self.positionsPoisInfo removeAllObjects];
    
    for (TTAlongRouteSearchResult *result in response.results) {
        NSString *markerString = [NSString stringWithFormat:@"%@, %@", result.poi.name, result.address.freeformAddress];
        [self createAndDisplayMarkerAtPosition:result.position withAnnotationImage:TTAnnotation.defaultAnnotationImage andBalloonText:markerString];
    }
    [self.tomtomMap zoomToAllAnnotations];
    [self dismissDialogInProgress];
}

- (void)search:(TTAlongRouteSearch *)search failedWithError:(TTResponseError *)error {
    [self dismissDialogInProgress];
    NSString *message = [NSString stringWithFormat:@"%@%@%@", @"No search results for ", self.searchBar.text, @". Please try another search term."];
    [self displayMessage:message];
}

- (UIView <TTCalloutView> *)annotationManager:(id<TTAnnotationManager>)manager viewForSelectedAnnotation:(TTAnnotation *)selectedAnnotation {
    NSString *selectedCoordinatesString = [self coordinatesToString:selectedAnnotation.coordinate];
    if ([selectedCoordinatesString isEqualToString:[self coordinatesToString:self.departurePosition]]) {
        return [[TTCalloutOutlineView alloc] init];
    } else {
        return [[TTCalloutOutlineView alloc ] initWithUIView:[self createCustomAnnotation:selectedAnnotation]];
    }
}

- (UIView <TTCalloutView> *)createCustomAnnotation:(TTAnnotation *)selectedAnnotation {
    CustomAnnotationView <TTCalloutView> *customAnnotation = [[NSBundle.mainBundle loadNibNamed:@"CustomAnnotationView" owner:self options:nil] firstObject];
    NSArray *annotationStringArray = [self.positionsPoisInfo[[self coordinatesToString:selectedAnnotation.coordinate]] componentsSeparatedByString:@","];
    customAnnotation.annotation = selectedAnnotation;
    customAnnotation.poiName.text = annotationStringArray[0];
    customAnnotation.poiAddress.text = annotationStringArray[1];
    customAnnotation.myDelegate = self;
    return customAnnotation;
}

- (NSString *)coordinatesToString:(CLLocationCoordinate2D)coords {
    return [NSString stringWithFormat:@"%@,%@", [@(coords.latitude) stringValue], [@(coords.longitude) stringValue]];
}

- (void)clearMap {
    [self disableSearchButtons];
    [self.tomtomMap.routeManager removeAllRoutes];
    [self.tomtomMap.annotationManager removeAllAnnotations];
    self.departurePosition = kCLLocationCoordinate2DInvalid;
    self.destinationPosition = kCLLocationCoordinate2DInvalid;
    self.wayPointPosition = kCLLocationCoordinate2DInvalid;
    self.fullRoute = nil;
    self.searchBar.text = @"";
}

- (void)enableSearchButtons {
    for (UIButton *button in self.searchButtons) {
        button.enabled = YES;
    }
    self.clearMapButton.enabled = YES;
}

- (void)disableSearchButtons {
    [self clearPoiButtonSelection];
    for (UIButton *button in self.searchButtons) {
        button.enabled = NO;
    }
    self.clearMapButton.enabled = NO;
}

- (TTRouteQuery *)createRouteQueryWithOrigin:(CLLocationCoordinate2D)origin andDestination:(CLLocationCoordinate2D)destination andWayPoint:(CLLocationCoordinate2D)wayPoint {
    TTRouteQueryBuilder *builder = [TTRouteQueryBuilder createWithDest:destination andOrig:origin];
    if (CLLocationCoordinate2DIsValid(wayPoint)) {
        [builder withWayPoints:@[[NSValue value:&wayPoint withObjCType:@encode(CLLocationCoordinate2D)]]];
    }
    return [builder build];
}

- (BOOL)isDestinationPositionSet {
    return CLLocationCoordinate2DIsValid(self.destinationPosition);
}

- (BOOL)isDeparturePositionSet {
    return CLLocationCoordinate2DIsValid(self.departurePosition);
}

- (void)mapView:(TTMapView *)mapView didLongPress:(CLLocationCoordinate2D)coordinate {
    if ([self isDeparturePositionSet] && [self isDestinationPositionSet]) {
        [self clearMap];
    } else {
        [self showDialogInProgress];
        [self handleLongPress:coordinate];
    }
}

- (void)handleApiError:(TTResponseError *)error {
    [self dismissDialogInProgress];
    [self displayMessage:error.localizedDescription];
}

- (void)handleLongPress:(CLLocationCoordinate2D)coordinate {
    TTReverseGeocoderQuery *query = [[TTReverseGeocoderQueryBuilder createWithCLLocationCoordinate2D:coordinate] build];
    
    [self.reverseGeocoder reverseGeocoderWithQuery:query completionHandle:^(TTReverseGeocoderResponse *response, TTResponseError *error) {
        if (error) {
            [self handleApiError:error];
        } else if (response.result.addresses.count > 0) {
            TTReverseGeocoderFullAddress *firstAddress = response.result.addresses.firstObject;
            NSString *address = firstAddress.address.freeformAddress ? firstAddress.address.freeformAddress : EMPTY_DEPARTURE_POSITION_TAG;
            [self processGeocoderResponse:firstAddress.position address:address];
        }
    }];
}

- (void)processGeocoderResponse:(CLLocationCoordinate2D)geocodedPosition address:(NSString *)address {
    if (![self isDeparturePositionSet]) {
        self.departurePosition = geocodedPosition;
        
        [self createAndDisplayMarkerAtPosition:self.departurePosition withAnnotationImage:self.departureImage andBalloonText:address];
        [self dismissDialogInProgress];
    } else {
        self.destinationPosition = geocodedPosition;
        [self drawRouteWithDeparture:self.departurePosition andDestination:self.destinationPosition];
    }
}

- (void)createAndDisplayMarkerAtPosition:(CLLocationCoordinate2D)coords withAnnotationImage:(TTAnnotationImage *)image andBalloonText:(NSString *)text {
    self.positionsPoisInfo[[self coordinatesToString:coords]] = text;
    [self.tomtomMap.annotationManager addAnnotation:[TTAnnotation annotationWithCoordinate:coords annotationImage:image anchor:TTAnnotationAnchorCenter type:TTAnnotationTypeFocal]];
}

- (void)drawRouteWithDeparture:(CLLocationCoordinate2D)departure andDestination:(CLLocationCoordinate2D)destination {
    [self drawRouteWithDeparture:departure andDestination:destination andWayPoint:kCLLocationCoordinate2DInvalid];
}

- (void)drawRouteWithDeparture:(CLLocationCoordinate2D)departure andDestination:(CLLocationCoordinate2D)destination andWayPoint:(CLLocationCoordinate2D)wayPoint {
    TTRouteQuery *query = [self createRouteQueryWithOrigin:departure andDestination:destination andWayPoint:wayPoint];
    [self.route planRouteWithQuery:query completionHandler:^(TTRouteResult *result, TTResponseError *error) {
        if (error) {
            [self handleApiError:error];
            [self clearMap];
        } else if (result.routes.count > 0) {
            [self addActiveRouteToMap:result.routes.firstObject];
            [self enableSearchButtons];
            [self dismissDialogInProgress];
        } else {
            [self dismissDialogInProgress];
        }
    }];
}

- (void)addActiveRouteToMap:(TTFullRoute *)route {
    [self.tomtomMap.routeManager removeAllRoutes];
    self.fullRoute = route;
    if (!CLLocationCoordinate2DIsValid(self.wayPointPosition)) {
        [self.tomtomMap.annotationManager removeAllAnnotations];
    }
    TTMapRoute *mapRoute = [TTMapRoute routeWithCoordinatesData:self.fullRoute withRouteStyle:TTMapRouteStyle.defaultActiveStyle imageStart:[TTMapRoute defaultImageDeparture] imageEnd:[TTMapRoute defaultImageDestination]];
    [self.tomtomMap.routeManager addRoute:mapRoute];
}

- (void)setWayPoint:(TTAnnotation *)annotation {
    [self showDialogInProgress];
    self.wayPointPosition = [annotation coordinate];
    [self.tomtomMap.annotationManager deselectAnnotation];
    [self drawRouteWithDeparture:self.departurePosition andDestination:self.destinationPosition andWayPoint:self.wayPointPosition];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if (self.fullRoute) {
        [self searchAlongTheRoute:self.searchBar.text];
    } else {
        [self displayMessage:@"Long press on the map to choose departure and destination points"];
    }
}

- (void)searchAlongTheRoute:(NSString *)searchText {
    [self showDialogInProgress];
    TTAlongRouteSearchQuery *alongRouteSearchQuery = [[[[TTAlongRouteSearchQueryBuilder alloc] initWithTerm:searchText withRoute:self.fullRoute withMaxDetourTime:SEARCH_MAX_DETOUR_TIME] withLimit:SEARCH_RESULTS_LIMIT] build];
    [self.alongRouteSearch searchWithQuery:alongRouteSearchQuery];
}

- (IBAction)clearMapButtonClicked:(id)sender {
    [self clearMap];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self clearPoiButtonSelection];
}

- (void)clearPoiButtonSelection {
    for (UIButton *button in self.searchButtons) {
        if (button.selected) {
            button.selected = NO;
        }
    }
}

- (IBAction)searchSelectionButtonClicked:(id)sender {
    [self clearPoiButtonSelection];
    UIButton *buttonClicked = (UIButton *) sender;
    buttonClicked.selected = YES;
    
    NSString *searchText;
    if (buttonClicked == self.gasStationButton) {
        searchText = @"Gas station";
    } else if (buttonClicked == self.restaurantButton) {
        searchText = @"Restaurant";
    } else if (buttonClicked == self.cashMachineButton) {
        searchText = @"ATM";
    }
    
    self.searchBar.text = searchText;
    [self searchAlongTheRoute:searchText];
}

- (void)displayMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    if (!self.presentedViewController || self.presentedViewController.isBeingDismissed) {
        [self presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, MESSAGE_DISPLAY_TIME_IN_SECONDS * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

- (void)mapView:(TTMapView *_Nonnull)mapView didSingleTap:(CLLocationCoordinate2D)coordinate {
    [self.view endEditing:YES];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    if (!self.keyboardShown) {
        [self adjustHeight:YES withNotification:notification];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    if (self.keyboardShown) {
        [self adjustHeight:NO withNotification:notification];
    }
}

- (void)keyboardDidShow:(NSNotification *)notification {
    self.keyboardShown = YES;
}

- (void)keyboardDidHide:(NSNotification *)notification {
    self.keyboardShown = NO;
}

- (void)adjustHeight:(Boolean)show withNotification:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGFloat bottomStackHeight = self.bottomStackHeight.constant;
    CGFloat changeInHeight = (CGRectGetHeight(keyboardFrame) - bottomStackHeight) * (show ? KEYBOARD_SHOW_MULTIPLIER : KEYBOARD_HIDE_MULTIPLIER);
    [UIView animateWithDuration:animationDuration animations:^{
        self.bottomConstraint.constant += changeInHeight;
    }];
}

@end
