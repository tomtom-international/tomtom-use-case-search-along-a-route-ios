#import "InfoScreenViewController.h"

@interface InfoScreenViewController ()

@property(weak, nonatomic) IBOutlet UIButton *backArrowButton;
@property(strong, nonatomic) IBOutlet UIView *topBarView;

@end

@implementation InfoScreenViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)backArrowTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
