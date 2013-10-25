//
//  ViewController.m
//  Fetch
//
//  Created by Joshua Barrow on 9/3/13.
//  Copyright (c) 2013 Jukaela Enterprises. All rights reserved.
//

#import "MainWindowController.h"
#import "Urls.h"
#import "NSUserDefaults+NSColor.h"
#import "Constants.h"
#import "Projects.h"
#import "Headers.h"
#import "Parameters.h"
#import "ProjectHandler.h"
#import "JsonViewerWindowController.h"
#import "CsvViewerWindowController.h"

#import "ProjectCell.h"
#import "UrlCell.h"
#import "NSTimer+Blocks.h"
#import "CHCSVParser.h"

@interface NSURLRequest(Private)
+(void)setAllowsAnyHTTPSCertificate:(BOOL)inAllow forHost:(NSString *)inHost;
@end

@interface MainWindowController ()

/// Backing store for headersTableView
@property (strong, nonatomic) NSMutableArray *headerDataSource;

/// Backing store for parametersTableView
@property (strong, nonatomic) NSMutableArray *paramDataSource;

/// Backing store for projectSourceList
@property (strong, nonatomic) NSMutableArray *projectList;

/// Backing store that holds all known header names
@property (strong, nonatomic) NSArray *headerNames;

/// The current Project
@property (strong, nonatomic) Projects *currentProject;

/// The current URl
@property (strong, nonatomic) Urls *currentUrl;

/// JSON Data returns from fetch action.  This is either an NSDictionary or NSArray
@property (strong, nonatomic) id responseData;

/// Reference to toolbar
@property (strong, nonatomic) CNSplitViewToolbar *toolbar;

/// Reference to remove button in toolbar
@property (strong, nonatomic) CNSplitViewToolbarButton *removeButton;

/// Reference to export button in toolbar
@property (strong, nonatomic) CNSplitViewToolbarButton *exportButton;

/// Mutable array that holds a reference to all url cells (Used for updating reachability status)
@property (strong, nonatomic) NSMutableArray *urlCellArray;

/// Used if the user has chosen to check reachability of URLs
@property (strong, nonatomic) NSTimer *pingTimer;

/// Do you expect the output to be in CSV format?
@property (nonatomic) BOOL isCSV;

/// Temp property for storying the clicked URL
@property (strong, nonatomic) Urls *clickedUrl;

/**
 * Setup the split view controller and it's controls
 */
-(void)setupSplitviewControls;

/**
 * Monitor NSUserDefaults for changes
 @param aNotification The notification that is produced when NSUserDefaults changes
 */
-(void)preferencesChanges:(NSNotification *)aNotification;

/**
 * Setup the segmented controls
 */
-(void)setupSegmentedControls;

/**
 * Unload all project and url data
 */
-(void)unloadData;

/**
 * Append specified output the outputTextView
 * @param text The text to append to the outputTextView
 * @param color The color to show the text in
 */
-(void)appendToOutput:(NSString *)text color:(NSColor *)color;

/**
 * Log specified NSMutableURLRequest to outputTextView
 * @param request The NSMutableURLRequest to log
 */
-(void)logReqest:(NSMutableURLRequest *)request;

/**
 * Add URL to Projects URL list if unique
 * @return Returns YES if the url was unique and added, NO if not
 */
-(BOOL)addToUrlListIfUnique;

/**
 * Load the URL into the user interface
 * @param url URL to load
 */
-(void)loadUrl:(Urls *)url;

/**
 * Load Specified Project into the user interface
 * @param project The Project to load
 */
-(void)loadProject:(Projects *)project;

/**
 * Add Project to Project Source List
 */
-(void)addProject;

/**
 * Remvoe the clicked or selected Project or URL from the source list
 */
-(void)removeProjectOrUrl;

/**
 * Create a timer with the specified time interval
 * @param timeInterval The time interval to create the timer
 */
-(void)createTimerWithTimeInterval:(NSTimeInterval)timeInterval;

/**
 * Check URL status for specified urlString
 * @param urlString The url to check the status of
 * @return URLStatus of the specified URL
 */
-(UrlStatus)urlVerification:(NSString *)urlString;

@end

@implementation MainWindowController

#pragma mark
#pragma mark Lifecycle

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    NSLog(@"%s", __FUNCTION__);
    
    self = [super initWithWindowNibName:windowNibName];
    
    if (self) {
        [self setHeaderDataSource:[[NSMutableArray alloc] init]];
        [self setParamDataSource:[[NSMutableArray alloc] init]];
        [self setHeaderNames:[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"HeaderNames" ofType:@"plist"]]];
        [self setProjectList:[NSMutableArray array]];
    }
    return self;
}

-(void)windowDidLoad
{
    NSLog(@"%s", __FUNCTION__);
    
    [super windowDidLoad];
    
    [[self splitView] setPosition:[[[NSUserDefaults standardUserDefaults] valueForKey:kSplitViewPosition] floatValue] ofDividerAtIndex:0];
    
    [[self customPayloadTextView] setAutomaticTextReplacementEnabled:NO];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesChanges:) name:NSUserDefaultsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addUrl:) name:kAddUrlNotification object:nil];
    
    BOOL checkSiteReachability = [[NSUserDefaults standardUserDefaults] boolForKey:kPingForReachability];
    
    NSString *frequencyToPing = [[NSUserDefaults standardUserDefaults] stringForKey:kFrequencyToPing];
    
    if (checkSiteReachability) {
        [self createTimerWithTimeInterval:[frequencyToPing intValue]];
    }
    else {
        for (UrlCell *cell in [self urlCellArray]) {
            [[cell statusImage] setHidden:YES];
        }
    }
    
    [[self projectSourceList] registerForDraggedTypes:@[NSFilenamesPboardType, NSFilesPromisePboardType]];
    
    [[self menuController] setMainWindowController:self];
    
    [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
    [[self projectSourceList] reloadData];
    
    [self preferencesChanges:nil];
    [self setupSegmentedControls];
    
    [[self customPayloadTextView] setValue:@"Place custom payload text here..." forKey:@"placeholderString"];
    
    [[self methodCombo] selectItemAtIndex:GET_METHOD];
    
    [self setupSplitviewControls];
    
    for (int index = 0; index < [[self projectList] count]; index++) {
        id item = [self projectList][index];
        
        if ([item isKindOfClass:[Projects class]]) {
            BOOL shouldExpand = [[(Projects *)item expanded] boolValue];
            
            if (shouldExpand) {
                [[[self projectSourceList] animator] expandItem:item];
            }
        }
    }
}

#pragma mark
#pragma mark Methods

- (void)setupSplitviewControls
{
    NSLog(@"%s", __FUNCTION__);
    
    [self setToolbar:[[CNSplitViewToolbar alloc] init]];
    
    NSMenu *contextMenu = [[NSMenu alloc] init];
    [contextMenu addItemWithTitle:@"Add New Project" action:@selector(addProject) keyEquivalent:[NSString blankString]];
    [contextMenu addItemWithTitle:@"Add New URL" action:@selector(addUrl:) keyEquivalent:[NSString blankString]];
    [contextMenu setDelegate:self];
    
    CNSplitViewToolbarButton *addButton = [[CNSplitViewToolbarButton alloc] initWithContextMenu:contextMenu];
    [addButton setImageTemplate:CNSplitViewToolbarButtonImageTemplateAdd];
    
    _removeButton = [[CNSplitViewToolbarButton alloc] init];
    [[self removeButton] setImageTemplate:CNSplitViewToolbarButtonImageTemplateRemove];
    [[self removeButton] setTarget:self];
    [[self removeButton] setAction:@selector(removeProjectOrUrl)];
    [[self removeButton] setEnabled:NO];
    
    _exportButton = [[CNSplitViewToolbarButton alloc] init];
    [[self exportButton] setImageTemplate:CNSplitViewToolbarButtonImageTemplateShare];
    [[self exportButton] setTarget:self];
    [[self exportButton] setAction:@selector(exportProject:)];
    [[self exportButton] setEnabled:NO];
    
    [[self toolbar] addItem:addButton align:CNSplitViewToolbarItemAlignLeft];
    [[self toolbar] addItem:[self removeButton] align:CNSplitViewToolbarItemAlignLeft];
    [[self toolbar] addItem:[self exportButton] align:CNSplitViewToolbarItemAlignRight];
    
    [[self splitView] setDelegate:self];
    [[self splitView] setToolbarDelegate:self];
    [[self splitView] attachToolbar:[self toolbar] toSubViewAtIndex:0 onEdge:CNSplitViewToolbarEdgeBottom];
    
    [[self splitView] showToolbarAnimated:NO];
}

-(void)preferencesChanges:(NSNotification *)aNotification
{
    NSLog(@"%s", __FUNCTION__);
    
    NSColor *backgroundColor = [[NSUserDefaults standardUserDefaults] colorForKey:kBackgroundColor];
    NSColor *foregroundColor = [[NSUserDefaults standardUserDefaults] colorForKey:kForegroundColor];
    
    [[self outputTextView] setTextColor:foregroundColor];
    [[self outputTextView] setBackgroundColor:backgroundColor];
    
    BOOL checkSiteReachability = [[NSUserDefaults standardUserDefaults] boolForKey:kPingForReachability];
    
    NSString *frequencyToPing = [[NSUserDefaults standardUserDefaults] stringForKey:kFrequencyToPing];
    
    if (checkSiteReachability) {
        if ([_pingTimer isValid]) {
            [_pingTimer invalidate];
        }
        
        [self createTimerWithTimeInterval:[frequencyToPing intValue]];
        
        for (UrlCell *cell in [self urlCellArray]) {
            [[cell statusImage] setHidden:NO];
        }
    }
    else {
        [[self pingTimer] invalidate];
        
        for (UrlCell *cell in [self urlCellArray]) {
            [[cell statusImage] setHidden:YES];
        }
    }
}

-(void)setupSegmentedControls
{
    NSLog(@"%s", __FUNCTION__);
    
    if ([[self headerDataSource] count] == 0) {
        [[self headerSegCont] setEnabled:NO forSegment:1];
    }
    else {
        [[self headerSegCont] setEnabled:YES forSegment:1];
    }
    
    if ([[self paramDataSource] count] == 0) {
        [[self paramSegCont] setEnabled:NO forSegment:1];
    }
    else {
        [[self paramSegCont] setEnabled:YES forSegment:1];
    }
}

-(void)unloadData
{
    [[self parseButton] setEnabled:NO];
    [[self fetchButton] setEnabled:NO];
    [[self urlTextField] setEnabled:NO];
    [[self urlDescriptionTextField] setEnabled:NO];
    
    [[self headerDataSource] removeAllObjects];
    [[self paramDataSource] removeAllObjects];
    
    [[self headersTableView] reloadData];
    [[self parametersTableView] reloadData];
}

#pragma mark
#pragma mark Request Logging

- (void)appendToOutput:(NSString *)text color:(NSColor *)color
{
    NSLog(@"%s", __FUNCTION__);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[text stringByAppendingString:@"\n"]];
        
        if (color) {
            [attributedString addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, [text length])];
        }
        
        [[[self outputTextView] textStorage] appendAttributedString:attributedString];
        [[self outputTextView] scrollRangeToVisible:NSMakeRange([[[self outputTextView] string] length], 0)];
        
        [[self clearOutputButton] setEnabled:YES];
    });
}

-(void)logReqest:(NSMutableURLRequest *)request
{
    NSLog(@"%s", __FUNCTION__);
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [self appendToOutput:kRequestSeparator color:[userDefaults colorForKey:kSeparatorColor]];
    [self appendToOutput:[request HTTPMethod] color:[userDefaults colorForKey:kSuccessColor]];
    [self appendToOutput:[NSString stringWithFormat:@"%@", [request allHTTPHeaderFields]] color:[userDefaults colorForKey:kSuccessColor]];
    [self appendToOutput:[[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding] color:[userDefaults colorForKey:kSuccessColor]];
}

#pragma mark
#pragma mark Url Handling

-(BOOL)addToUrlListIfUnique
{
    NSLog(@"%s", __FUNCTION__);
    
    if (![[self urlTextField] stringValue] || [[[self urlTextField] stringValue] isEqualToString:[NSString blankString]]) {
        return NO;
    }
    
    BOOL validPrefix = [[[self urlTextField] stringValue] hasValidURLPrefix];
    
    if (!validPrefix) {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Invalid URL"
                                              defaultButton:@"OK"
                                            alternateButton:nil
                                                otherButton:nil
                                  informativeTextWithFormat:@"The url must be prefixed with the URL type.  Valid types are http and https"];
        
        [errorAlert runModal];
        
        return NO;
    }
    
    BOOL addURL = YES;
    
    for (Urls *tempURL in [[self currentProject] urls]) {
        if ([[tempURL url] isEqualToString:[[self urlTextField] stringValue]]) {
            addURL = NO;
            
            break;
        }
    }
    
    if (addURL) {
        Urls *tempUrl = [Urls create];
        
        [tempUrl setCreatedAt:[NSDate date]];
        [tempUrl setMethod:[NSNumber numberWithInteger:[[self methodCombo] indexOfSelectedItem]]];
        [tempUrl setUrl:[[self urlTextField] stringValue]];
        
        [self setCurrentUrl:tempUrl];
        [[self exportButton] setEnabled:YES];
        [[self removeButton] setEnabled:YES];
        
        if ([self currentProject]) {
            [[self currentProject] addUrlsObject:tempUrl];
            
            [[self currentProject] save];
        }
        else {
            [tempUrl save];
        }
    }
    
    return YES;
}

-(void)loadUrl:(Urls *)url
{
    NSLog(@"%s", __FUNCTION__);
    
    [[self fetchButton] setEnabled:YES];
    
    Urls *tempUrl = url;
    
    [self setCurrentUrl:tempUrl];
    
    [[self methodCombo] selectItemAtIndex:[[tempUrl method] intValue]];
    [[self methodCombo] setEnabled:YES];
    
    [[self customPayloadTextView] setString:[[tempUrl customPayload] hasValue] ? [tempUrl customPayload] : [NSString blankString]];
    [[self urlDescriptionTextField] setStringValue:[[tempUrl urlDescription] hasValue] ? [tempUrl urlDescription] : [NSString blankString]];
    [[self methodCombo] selectItemAtIndex:[[tempUrl method] integerValue]];
    
    int index = 0;
    
    [[self headerDataSource] removeAllObjects];
    [[self headersTableView] reloadData];
    
    if ([[tempUrl headers] count] > 0) {
        [[self headersTableView] beginUpdates];
        
        for (Headers *tempHeader in [tempUrl headers]) {
            [[self headerDataSource] addObject:tempHeader];
            
            [[self headersTableView] insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index] withAnimation:NSTableViewAnimationEffectNone];
            
            index++;
        }
        
        [[self headersTableView] endUpdates];
        
        if ([[self headersTableView] numberOfRows] > 0) {
            [[self headerSegCont] setEnabled:YES forSegment:1];
        }
    }
    
    [[self paramDataSource] removeAllObjects];
    [[self parametersTableView] reloadData];
    
    if ([[tempUrl parameters] count] > 0) {
        index = 0;
        
        [[self parametersTableView] beginUpdates];
        
        for (Parameters *tempParam in [tempUrl parameters]) {
            [[self paramDataSource] addObject:tempParam];
            
            [[self parametersTableView] insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index] withAnimation:NSTableViewAnimationEffectNone];
            
            index++;
        }
        
        [[self parametersTableView] endUpdates];
        
        if ([[self parametersTableView] numberOfRows] > 0) {
            [[self paramSegCont] setEnabled:YES forSegment:1];
        }
    }
    
    if ([tempUrl customPayload] && [[tempUrl customPayload] length] > 0) {
        [[self customPostBodyCheckBox] setState:NSOnState];
        
        [[[self customPayloadTextView] enclosingScrollView] setHidden:NO];
        
        [[[self paramSegCont] animator] setAlphaValue:0.0];
        [[self paramSegCont] setEnabled:NO];
    }
    else {
        [[self customPostBodyCheckBox] setState:NSOffState];
        
        [[[self customPayloadTextView] enclosingScrollView] setHidden:YES];
        
        [[self paramSegCont] setEnabled:YES];
        [[[self paramSegCont] animator] setAlphaValue:1.0];
    }
}

-(void)addUrl:(id)sender
{
    Projects *tempProject = nil;
    
    if ([sender isKindOfClass:[NSNotification class]]) {
        tempProject = [(NSNotification *)sender userInfo][@"project"];
    }
    else {
        tempProject = [self currentProject];
    }
    
    if (tempProject) {
        Urls *tempUrl = [Urls create];
        
        [tempUrl setCreatedAt:[NSDate date]];
        [tempUrl setUrlDescription:@"New URL"];
        
        [tempProject addUrlsObject:tempUrl];
        [tempProject save];
        
        [[self urlCellArray] removeAllObjects];
        
        [[self projectSourceList] reloadData];
        
        [[self fetchButton] setEnabled:YES];
        [[self urlTextField] setEnabled:YES];
        [[self urlDescriptionTextField] setEnabled:YES];
        
        [[self projectSourceList] expandItem:[[self projectSourceList] itemAtRow:[[self projectSourceList] rowForItem:[tempUrl project]]]];
    }
}

#pragma mark
#pragma mark Project Handling

-(void)importProject:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    
    [openPanel setTitle:@"Import"];
    [openPanel setAllowedFileTypes:@[@"fetch"]];
    [openPanel setAllowsMultipleSelection:NO];
    
    if ([openPanel runModal] == NSOKButton) {
        if ([ProjectHandler importFromPath:[[openPanel URL] path]]) {
            [[self projectList] removeAllObjects];
            
            [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
            
            [[self urlCellArray] removeAllObjects];
            
            [[self projectSourceList] reloadData];
        }
    }
}

-(void)exportProject:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    
    id selectedProject = [[self projectSourceList] itemAtRow:[[self projectSourceList] selectedRow]];
    
    if ([selectedProject isKindOfClass:[Urls class]]) {
        selectedProject = [selectedProject project];
    }
    
    if (!selectedProject) {
        selectedProject = [self currentProject];
    }
    
    NSAssert(selectedProject, @"selectedProject cannot be nil in %s", __FUNCTION__);
    
    [savePanel setTitle:@"Export"];
    [savePanel setNameFieldStringValue:[[selectedProject name] stringByAppendingPathExtension:@"fetch"]];
    
    if ([savePanel runModal] == NSOKButton) {
        [ProjectHandler exportProject:selectedProject toUrl:[savePanel URL]];
    }
}

-(void)deleteProject:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    id item = [[self projectSourceList] itemAtRow:[[self projectSourceList] selectedRow]];
    
    if ([item isKindOfClass:[Projects class]]) {
        Projects *tempProject = item;
        
        [[self projectList] removeObject:tempProject];
        
        if (tempProject == [self currentProject]) {
            [self setCurrentProject:nil];
            [[self exportButton] setEnabled:NO];
            [[self removeButton] setEnabled:NO];
            
            [self unloadData];
        }
        
        [tempProject delete];
    }
    else {
        Urls *tempUrl = item;
        
        if (tempUrl == [self currentUrl]) {
            [self setCurrentUrl:nil];
            
            [self unloadData];
        }
        
        [tempUrl delete];
    }
    
    [[self urlCellArray] removeAllObjects];
    
    [[self projectSourceList] reloadData];
}

-(void)loadProject:(Projects *)project
{
    NSLog(@"%s", __FUNCTION__);
    
    [[self headerDataSource] removeAllObjects];
    [[self headersTableView] reloadData];
    
    [[self paramDataSource] removeAllObjects];
    [[self parametersTableView] reloadData];
    
    [[self methodCombo] selectItemAtIndex:GET_METHOD];
    
    [[self urlTextField] setStringValue:[NSString blankString]];
    [[self urlDescriptionTextField] setStringValue:[NSString blankString]];
    
    [[self customPayloadTextView] setString:[NSString blankString]];
    [[self customPostBodyCheckBox] setState:NSOffState];
    
    [self setCurrentProject:project];
    [[self exportButton] setEnabled:YES];
    [[self removeButton] setEnabled:YES];
    
    [[self fetchButton] setEnabled:YES];
    [[self urlTextField] setEnabled:YES];
    [[self urlDescriptionTextField] setEnabled:YES];
    [[self methodCombo] setEnabled:YES];
    
    [self setupSegmentedControls];
}

-(void)saveLog
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    
    [savePanel setTitle:@"Save Log"];
    [savePanel setNameFieldStringValue:[@"LogFile" stringByAppendingPathExtension:@"txt"]];
    
    if ([savePanel runModal] == NSOKButton) {
        NSError *error = nil;
        
        [[[self outputTextView] string] writeToFile:[[savePanel URL] path] atomically:YES encoding:NSUTF8StringEncoding error:&error];
        
        if (error) {
            NSAlert *errorAlert = [NSAlert alertWithError:error];
            
            [errorAlert runModal];
        }
    }
}

-(void)addProject
{
    [self unloadData];
    
    [self setCurrentUrl:nil];
    
    [[self urlDescriptionTextField] setStringValue:[NSString blankString]];
    [[self urlTextField] setStringValue:[NSString blankString]];
    [[self urlDescriptionTextField] setEnabled:NO];
    [[self urlTextField] setEnabled:NO];
    [[self fetchButton] setEnabled:NO];
    
    [self setResponseDict:nil];
    [self setRequestDict:nil];
    
    Projects *tempProject = [Projects create];
    
    [tempProject setName:@"Project Name"];
    [tempProject save];
    
    [self setCurrentProject:tempProject];
    [[self exportButton] setEnabled:YES];
    [[self removeButton] setEnabled:YES];
    
    [[self projectList] addObject:tempProject];
    
    [[self urlCellArray] removeAllObjects];
    
    [[self projectSourceList] reloadData];
    [[self projectSourceList] selectRowIndexes:[NSIndexSet indexSetWithIndex:[[self projectSourceList] numberOfRows] - 1] byExtendingSelection:NO];
}

-(void)removeProjectOrUrl
{
    id item = [[self projectSourceList] itemAtRow:[[self projectSourceList] selectedRow]];
    
    if ([item isKindOfClass:[Projects class]]) {
        NSString *messageText = [NSString stringWithFormat:@"Delete project \"%@\"?  You cannot undo this action.", [item name]];
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"Delete Project?" defaultButton:@"Delete" alternateButton:nil otherButton:@"Cancel" informativeTextWithFormat:messageText, nil];
        
        if ([alert runModal] == NSOKButton) {
            [[self projectList] removeObject:item];
            
            if (item == [self currentProject]) {
                [self setCurrentProject:nil];
                
                [[self exportButton] setEnabled:NO];
                [[self removeButton] setEnabled:NO];
                
                [[self parseButton] setEnabled:NO];
                [[self fetchButton] setEnabled:NO];
                [[self urlTextField] setEnabled:NO];
                [[self urlDescriptionTextField] setEnabled:NO];
                
                [[self headerDataSource] removeAllObjects];
                [[self paramDataSource] removeAllObjects];
                
                [[self headersTableView] reloadData];
                [[self parametersTableView] reloadData];
            }
            
            [item delete];
        }
    }
    else if ([item isKindOfClass:[Urls class]]) {
        NSString *messageText = @"Delete url? You cannot undo this action.";
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"Delete URL?" defaultButton:@"Delete" alternateButton:nil otherButton:@"Cancel" informativeTextWithFormat:messageText, nil];
        
        if ([alert runModal] == NSOKButton) {
            [item delete];
            
            if (item == [self currentUrl]) {
                [[self parseButton] setEnabled:NO];
                [[self fetchButton] setEnabled:NO];
                
                [[self urlTextField] setStringValue:[NSString blankString]];
                [[self urlDescriptionTextField] setStringValue:[NSString blankString]];
                
                [[self methodCombo] setEnabled:NO];
                
                [[self headerDataSource] removeAllObjects];
                [[self paramDataSource] removeAllObjects];
                
                [[self headersTableView] reloadData];
                [[self parametersTableView] reloadData];
            }
        }
    }
    
    [[self urlCellArray] removeAllObjects];
    
    [[self projectSourceList] reloadData];
}

#pragma mark
#pragma mark IBActions

-(IBAction)fetchAction:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSMutableString *parameters = [[NSMutableString alloc] init];
    
    [[self fetchButton] setHidden:YES];
    [[self progressIndicator] setHidden:NO];
    [[self progressIndicator] startAnimation:self];
    
    if ([[[self urlTextField] stringValue] isEqualToString:[NSString blankString]] || ![[self urlTextField] stringValue]) {
        NSAlert *alert = [[NSAlert alloc] init];
        
        [alert addButtonWithTitle:@"OK"];
        [alert setMessageText:@"Unable to Fetch."];
        [alert setInformativeText:@"You must specify a URL."];
        [alert setAlertStyle:NSWarningAlertStyle];
        
        [alert runModal];
        
        [[self fetchButton] setHidden:NO];
        [[self progressIndicator] stopAnimation:self];
        [[self progressIndicator] setHidden:YES];
        
        return;
    }
    
    if ([self addToUrlListIfUnique]) {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
        
        [request setHTTPMethod:[[self methodCombo] objectValueOfSelectedItem]];
        
        for (Headers *tempHeader in [self headerDataSource]) {
            [request setValue:[tempHeader value] forHTTPHeaderField:[tempHeader name]];
        }
        
        if ([[self customPostBodyCheckBox] state] == NSOnState) {
            [request setHTTPBody:[[[self customPayloadTextView] string] dataUsingEncoding:NSUTF8StringEncoding]];
            [[self currentUrl] setCustomPayload:[[self customPayloadTextView] string]];
            [[self currentUrl] save];
        }
        else {
            [[self currentUrl] setCustomPayload:nil];
            [[self currentUrl] save];
            
            for (Parameters *tempParam in [self paramDataSource]) {
                if (tempParam == [[self paramDataSource] first]) {
                    [parameters appendString:[NSString stringWithFormat:@"?%@=%@", [tempParam name], [tempParam value]]];
                }
                else {
                    [parameters appendString:[NSString stringWithFormat:@"&%@=%@", [tempParam name], [tempParam value]]];
                }
            }
        }
        
        if ([parameters length] > 0) {
            [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [[self urlTextField] stringValue], parameters]]];
        }
        else {
            [request setURL:[NSURL URLWithString:[[self urlTextField] stringValue]]];
        }
        
        if ([[self logRequestCheckBox] state] == NSOnState) {
            [self logReqest:request];
        }
        
        [self setRequestDict:[request allHTTPHeaderFields]];
        
        [NSURLRequest setAllowsAnyHTTPSCertificate:YES forHost:[[request URL] host]];
        
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response,
                                                                                                                NSData *data,
                                                                                                                NSError *connectionError) {
            NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
            NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
            NSInteger responseCode = [urlResponse statusCode];
            NSString *responseCodeString = [NSString stringWithFormat:@"Response - %li\n", responseCode];
            
            [self appendToOutput:kResponseSeparator color:[userDefaults colorForKey:kSeparatorColor]];
            
            if (NSLocationInRange(responseCode, NSMakeRange(200, (299 - 200)))) {
                [self appendToOutput:responseCodeString color:[userDefaults colorForKey:kSuccessColor]];
            }
            else {
                [self appendToOutput:responseCodeString color:[userDefaults colorForKey:kFailureColor]];
            }
            
            [self appendToOutput:[NSString stringWithFormat:@"%@", [urlResponse allHeaderFields]] color:[userDefaults colorForKey:kSuccessColor]];
            
            [self setResponseDict:[urlResponse allHeaderFields]];
            
            if (!connectionError) {
                [self setResponseData:data];
                
                [[self parseButton] setEnabled:YES];
                
                id jsonData = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                
                if (jsonData) {
                    NSData *jsonHolder = [NSJSONSerialization dataWithJSONObject:jsonData options:NSJSONWritingPrettyPrinted error:nil];
                    
                    if (jsonHolder) {
                        [self appendToOutput:[[NSString alloc] initWithData:jsonHolder encoding:NSUTF8StringEncoding] color:[userDefaults colorForKey:kForegroundColor]];
                    }
                }
                else {
                    [self appendToOutput:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] color:[userDefaults colorForKey:kForegroundColor]];
                }
                
                if ([[[self jsonWindow] window] isVisible]) {
                    [self showJson:nil];
                }
            }
            else {
                NSAlert *errorAlert = [NSAlert alertWithError:connectionError];
                
                [errorAlert runModal];
            }
            
            [[self fetchButton] setHidden:NO];
            [[self progressIndicator] stopAnimation:self];
            [[self progressIndicator] setHidden:YES];
        }];
        
        [[self urlCellArray] removeAllObjects];
        
        [[self projectSourceList] reloadData];
    }
}

-(IBAction)headerSegContAction:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSSegmentedControl *tempSegCont = sender;
    
    if ([tempSegCont selectedSegment] == 0) {
        Headers *tempHeader = [Headers create];
        
        [tempHeader setName:@"Choose or insert header name"];
        [tempHeader setValue:kInsertValue];
        
        [tempHeader save];
        
        [[self currentUrl] addHeadersObject:tempHeader];
        
        [[self headerDataSource] addObject:tempHeader];
        
        [[self headersTableView] beginUpdates];
        [[self headersTableView] insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:([[self headerDataSource] count] - 1)] withAnimation:NSTableViewAnimationEffectFade];
        [[self headersTableView] endUpdates];
    }
    else {
        if ([[self headersTableView] selectedRow] == -1) {
            return;
        }
        
        if ([self currentProject]) {
            Headers *tempHeader = [self headerDataSource][[[self headersTableView] selectedRow]];
            
            [tempHeader delete];
        }
        
        [[self headerDataSource] removeObjectAtIndex:[[self headersTableView] selectedRow]];
        
        [[self headersTableView] reloadData];
    }
    
    [self setupSegmentedControls];
}

-(IBAction)parameterSegContAction:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSSegmentedControl *tempSegCont = sender;
    
    if ([tempSegCont selectedSegment] == 0) {
        Parameters *tempParam = [Parameters create];
        
        [tempParam setName:kInsertName];
        [tempParam setValue:kInsertValue];
        [tempParam save];
        
        [[self currentUrl] addParametersObject:tempParam];
        
        [[self paramDataSource] addObject:tempParam];
        
        [[self parametersTableView] beginUpdates];
        [[self parametersTableView] insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:([[self paramDataSource] count] - 1)] withAnimation:NSTableViewAnimationEffectFade];
        [[self parametersTableView] endUpdates];
    }
    else {
        if ([[self parametersTableView] selectedRow] == -1) {
            return;
        }
        
        if ([self currentProject]) {
            Parameters *tempParam = [self paramDataSource][[[self parametersTableView] selectedRow]];
            
            [tempParam delete];
        }
        
        [[self paramDataSource] removeObjectAtIndex:[[self parametersTableView] selectedRow]];
        
        [[self parametersTableView] reloadData];
    }
    
    [self setupSegmentedControls];
}

-(IBAction)customPostBodyAction:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    if ([[self customPostBodyCheckBox] state] == NSOnState) {
        [[[self customPayloadTextView] enclosingScrollView] setHidden:NO];
        
        [[[self paramSegCont] animator] setAlphaValue:0.0];
        [[self paramSegCont] setEnabled:NO];
    }
    else {
        [[[self customPayloadTextView] enclosingScrollView] setHidden:YES];
        
        [[self paramSegCont] setEnabled:YES];
        [[[self paramSegCont] animator] setAlphaValue:1.0];
    }
}

-(IBAction)clearOutput:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    [[self outputTextView] setString:[NSString blankString]];
    
    [[self clearOutputButton] setEnabled:NO];
}

-(IBAction)showJson:(id)sender
{
    NSError *error = nil;
    
    id jsonData = [NSJSONSerialization JSONObjectWithData:[self responseData] options:0 error:&error];
    
    if (jsonData) {
        if (![self jsonWindow]) {
            [self setJsonWindow:[[JsonViewerWindowController alloc] initWithWindowNibName:kJsonViewerWindowXib json:jsonData]];
        }
        else {
            [[self jsonWindow] setJsonData:jsonData];
            [[[self jsonWindow] outlineView] reloadData];
        }
        
        [[[self jsonWindow] window] makeKeyAndOrderFront:self];
    }
    else {
        NSAlert *errorAlert = [NSAlert alertWithError:error];
        
        [errorAlert runModal];
    }
}

-(IBAction)showCsv:(id)sender
{
    NSArray *rows = [NSArray arrayWithContentsOfString:[[NSString alloc] initWithData:[self responseData] encoding:NSUTF8StringEncoding] options:CHCSVParserOptionsSanitizesFields|CHCSVParserOptionsStripsLeadingAndTrailingWhitespace];
    
    if (rows) {
        [self setCsvWindow:[[CsvViewerWindowController alloc] initWithWindowNibName:@"CsvViewerWindowController" dataSource:rows]];
        
        [[self csvWindow] setNumberOfColumns:[rows[0] count]];
        
        [[[self csvWindow] window] makeKeyAndOrderFront:self];
    }
    else {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Error" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"The data is not in the correct format."];
        
        [errorAlert runModal];
    }
}

-(IBAction)duplicateURL:(id)sender
{
    Projects *tempProject = [[self clickedUrl] project];
    
    Urls *oldUrl = [self clickedUrl];
    Urls *duplicateUrl = [Urls create];
    
    NSMutableSet *oldHeaders = [[NSMutableSet alloc] init];
    NSMutableSet *oldParams = [[NSMutableSet alloc] init];

    for (Headers *tempHeader in [oldUrl headers]) {
        Headers *newTempHeader = [Headers create];
        
        [newTempHeader setValue:[tempHeader value]];
        [newTempHeader setName:[tempHeader name]];
        
        [oldHeaders addObject:newTempHeader];
    }
    
    for (Parameters *tempParam in [oldUrl parameters]) {
        Parameters *newTempParam = [Headers create];
        
        [newTempParam setValue:[tempParam value]];
        [newTempParam setName:[tempParam name]];
        
        [oldParams addObject:newTempParam];
    }
    
    [duplicateUrl setUrl:[oldUrl url]];
    [duplicateUrl setHeaders:oldHeaders];
    [duplicateUrl setParameters:oldParams];
    [duplicateUrl setMethod:[oldUrl method]];
    [duplicateUrl setCustomPayload:[oldUrl customPayload]];
    [duplicateUrl setCreatedAt:[NSDate date]];
    
    if ([[oldUrl urlDescription] length] > 0) {
        [duplicateUrl setUrlDescription:[NSString stringWithFormat:@"%@ (Duplicate)", [oldUrl urlDescription]]];
    }
    else {
        [duplicateUrl setUrlDescription:[NSString stringWithFormat:@"%@ (Duplicate)", [oldUrl url]]];
    }
    
    [tempProject addUrlsObject:duplicateUrl];
    [tempProject save];
    
    [[self projectSourceList] reloadData];
}

-(IBAction)parseAction:(id)sender
{
    [NSMenu popUpContextMenu:[self parseMenu] withEvent:[[NSApplication sharedApplication] currentEvent] forView:sender];
}

#pragma mark
#pragma mark NSControlTextDelegate

- (void)controlTextDidChange:(NSNotification *)notification
{
    if ([notification object] == [self urlTextField]) {
        if ([[[self urlTextField] stringValue] length] > 0) {
            if ([self currentUrl]) {
                [[self currentUrl] setUrl:[[self urlTextField] stringValue]];
                [[self currentUrl] save];
            }
        }
        else {
            [[self fetchButton] setEnabled:NO];
        }
    }
}

-(void)controlTextDidEndEditing:(NSNotification *)notification
{
    if ([notification object] == [self urlTextField]) {
        if ([[notification userInfo][@"NSTextMovement"] intValue] == NSReturnTextMovement) {
            [self fetchAction:nil];
        }
    }
    else if ([notification object] == [self urlDescriptionTextField]) {
        if ([self currentUrl]) {
            [[self currentUrl] setUrlDescription:[[self urlDescriptionTextField] stringValue]];
            [[self currentUrl] save];
            
            [[self projectSourceList] beginUpdates];
            [[self projectSourceList] reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:[[self projectSourceList] selectedRow]] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
            [[self projectSourceList] endUpdates];
        }
    }
    else if ([[[notification object] superview] isKindOfClass:[ProjectCell class]]) {
        ProjectCell *tempCell = (ProjectCell *)[[notification object] superview];
        NSTextField *tempTextField = [notification object];
        Projects *project = [tempCell project];
        
        [project setName:[tempTextField stringValue]];
        [project save];
    }
}

-(void)textDidEndEditing:(NSNotification *)notification
{
    if ([notification object] == [self customPayloadTextView]) {
        Urls *tempUrl = [self currentUrl];
        
        if (tempUrl) {
            if ([[self customPostBodyCheckBox] state] == NSOnState) {
                [tempUrl setCustomPayload:[[self customPayloadTextView] string]];
                
                [tempUrl save];
            }
        }
    }
}

#pragma mark
#pragma mark NSTableViewDataSource

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == [self headersTableView]) {
        return [[self headerDataSource] count];
    }
    else {
        return [[self paramDataSource] count];
    }
}

#pragma mark
#pragma mark NSTableViewDelegate

-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSString *identifier = [tableColumn identifier];
    
    if (tableView == [self headersTableView]) {
        Headers *tempHeader = [self headerDataSource][row];
        
        if ([identifier isEqualToString:kHeaderName]) {
            return [tempHeader name];
        }
        else {
            return [tempHeader value];
        }
    }
    else {
        Parameters *tempParam = [self paramDataSource][row];
        
        if ([identifier isEqualToString:kParameterName]) {
            return [tempParam name];
        }
        else {
            return [tempParam value];
        }
    }
}

-(void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSString *identifier = [tableColumn identifier];
    
    if ([self currentProject]) {
        [self addToUrlListIfUnique];
        
        if (tableView == [self headersTableView]) {
            Headers *tempHeader = nil;
            
            if ([identifier isEqualToString:kHeaderName]) {
                if (([[self headerDataSource] count] - 1) >= row) {
                    tempHeader = [self headerDataSource][row];
                }
                else {
                    tempHeader = [Headers create];
                    
                    [[self currentUrl] addHeadersObject:tempHeader];
                }
                
                [tempHeader setName:object];
                [tempHeader save];
            }
            else {
                if (([[self headerDataSource] count] - 1) >= row) {
                    tempHeader = [self headerDataSource][row];
                }
                else {
                    tempHeader = [Headers create];
                    
                    [[self currentUrl] addHeadersObject:tempHeader];
                }
                
                [tempHeader setValue:object];
                [tempHeader save];
            }
            
            [[self headerDataSource] replaceObjectAtIndex:row withObject:tempHeader];
        }
        else {
            Parameters *tempParam = nil;
            
            if ([identifier isEqualToString:kParameterName]) {
                if (([[self paramDataSource] count] - 1) >= row) {
                    tempParam = [self paramDataSource][row];
                }
                else {
                    tempParam = [Parameters create];
                    
                    [[self currentUrl] addParametersObject:tempParam];
                }
                
                [tempParam setName:object];
                [tempParam save];
            }
            else {
                if (([[self paramDataSource] count] - 1) >= row) {
                    tempParam = [self paramDataSource][row];
                }
                else {
                    tempParam = [Parameters create];
                    
                    [[self currentUrl] addParametersObject:tempParam];
                }
                
                [tempParam setValue:object];
                [tempParam save];
            }
            
            [[self paramDataSource] replaceObjectAtIndex:row withObject:tempParam];
        }
    }
}

#pragma mark
#pragma mark NSComboBoxDelegate

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] == [self methodCombo]) {
        if ([self currentUrl]) {
            [self addToUrlListIfUnique];
            
            [[self currentUrl] setMethod:[NSNumber numberWithInteger:[[self methodCombo] indexOfSelectedItem]]];
            [[self currentUrl] save];
        }
    }
}

#pragma mark
#pragma mark NSOutlineViewDataSource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (!item) {
        return [[self projectList] objectAtIndex:index];
    }
    else {
        Projects *tempProject = item;
        
        NSArray *tempArray = [NSArray arrayWithArray:[[[tempProject urls] allObjects] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]]]];
        
        return tempArray[index];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if ([item isKindOfClass:[Projects class]]) {
        Projects *tempProject = item;
        
        if ([[tempProject urls] count] > 0) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
    return YES;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (!item) {
        return [[self projectList] count];
    }
    else {
        if ([item isKindOfClass:[Projects class]]) {
            Projects *tempProject = item;
            
            return [[tempProject urls] count];
        }
    }
    
    return 0;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    static NSString *const CellIdentifier = @"DataCell";
    static NSString *const UrlCellIdentifier = @"UrlCell";
    
    if ([item isKindOfClass:[Projects class]]) {
        ProjectCell *cell = [outlineView makeViewWithIdentifier:CellIdentifier owner:self];
        
        Projects *tempProject = item;
        
        [[cell textField] setStringValue:[tempProject name]];
        [cell setProject:tempProject];
        
        [[cell addUrlButton] setHidden:NO];
        
        return cell;
    }
    else {
        if (![self urlCellArray]) {
            [self setUrlCellArray:[NSMutableArray array]];
        }
        
        UrlCell *cell = [outlineView makeViewWithIdentifier:UrlCellIdentifier owner:self];
        
        Urls *tempUrl = item;
        
        [cell setCurrentUrl:tempUrl];
        
        if ([[cell currentUrl] siteStatus]) {
            [[cell statusImage] setImage:[NSImage imageNamed:[tempUrl siteStatus]]];
        }
        
        if ([tempUrl urlDescription]) {
            [[cell textField] setStringValue:[tempUrl urlDescription]];
        }
        else {
            [[cell textField] setStringValue:[tempUrl url]];
        }
        
        [[cell textField] setToolTip:[tempUrl url]];
        
        [[self urlCellArray] addObject:cell];
        
        return cell;
    }
}

#pragma mark
#pragma mark NSOutlineViewDelegate

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    Projects *tempProject = item;
    
    [tempProject setName:object];
    
    [tempProject save];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification;
{
    Projects *project = [notification userInfo][@"NSObject"];
    
    [project setExpanded:@YES];
    [project save];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    Projects *project = [notification userInfo][@"NSObject"];
    
    [project setExpanded:@NO];
    [project save];
}

-(void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    NSOutlineView *outlineView = [notification object];
    
    id selectedItem = [outlineView itemAtRow:[outlineView selectedRow]];
    
    if ([selectedItem isKindOfClass:[Projects class]]) {
        Projects *tempProject = selectedItem;
        
        [self loadProject:tempProject];
    }
    else {
        Urls *tempItem = selectedItem;
        
        if ([self currentProject] != [tempItem project]) {
            [self loadProject:[selectedItem project]];
        }
        
        if ([tempItem url]) {
            [[self urlTextField] setStringValue:[tempItem url]];
        }
        else {
            [[self urlTextField] setStringValue:[NSString blankString]];
        }
        
        [self loadUrl:tempItem];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    return YES;
}

#pragma mark
#pragma mark NSOutlineViewDelegate Drag Support

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    return NSDragOperationCopy;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    NSURL *draggedUrl = [NSURL URLWithString:[[info draggingPasteboard] stringForType:kUTITypePublicFile]];
    
    if ([ProjectHandler importFromPath:[draggedUrl path]]) {
        [[self projectList] removeAllObjects];
        
        [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
        
        [[self urlCellArray] removeAllObjects];
        
        [[self projectSourceList] reloadData];
        
        return YES;
    }
    
    return NO;
}

#pragma mark
#pragma mark CNSplitViewToolbarDelegate

- (NSUInteger)toolbarAttachedSubviewIndex:(CNSplitViewToolbar *)theToolbar
{
    return kProjectListSplitViewSide;
}

#pragma mark
#pragma mark NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    return kMinimumSplitViewSize;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex
{
    [[NSUserDefaults standardUserDefaults] setObject:@(proposedPosition) forKey:kSplitViewPosition];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    return proposedPosition;
}

#pragma mark
#pragma mark UrlCell Handlers

-(void)createTimerWithTimeInterval:(NSTimeInterval)timeInterval
{
    _pingTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval block:^{
        
        for (UrlCell *cell in [self urlCellArray]) {
            if (![[[cell currentUrl] url] isEqualToString:[NSString blankString]]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    UrlStatus status = [self urlVerification:[[cell currentUrl] url]];
                    
                    if (status == SiteUp) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[cell statusImage] setImage:[NSImage imageNamed:NSImageNameStatusAvailable]];
                            
                            [[cell currentUrl] setSiteStatus:NSImageNameStatusAvailable];
                            [[cell currentUrl] save];
                        });
                    }
                    else if (status == SiteInconclusive) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[cell statusImage] setImage:[NSImage imageNamed:NSImageNameStatusUnavailable]];
                            
                            [[cell currentUrl] setSiteStatus:NSImageNameStatusPartiallyAvailable];
                            [[cell currentUrl] save];
                        });
                    }
                    else if (status == SiteDown) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[cell statusImage] setImage:[NSImage imageNamed:NSImageNameStatusPartiallyAvailable]];
                            
                            [[cell currentUrl] setSiteStatus:NSImageNameStatusUnavailable];
                            [[cell currentUrl] save];
                        });
                    }
                });
            }
        }
    } repeats:YES];
}

-(UrlStatus)urlVerification:(NSString *)urlString
{
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];
    NSHTTPURLResponse *response = nil;
    
    if ([NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil]) {
        if (NSLocationInRange([response statusCode], NSMakeRange(200, (299 - 200)))) {
            return SiteUp;
        }
        else if (NSLocationInRange([response statusCode], NSMakeRange(500, (599 - 500)))) {
            return SiteInconclusive;
        }
        else {
            return SiteDown;
        }
    }
    
    return SiteDown;
}

#pragma mark -
#pragma mark NSMenuDelegate

-(void)menuNeedsUpdate:(NSMenu *)menu
{
    NSInteger clickedRow = [[self projectSourceList] clickedRow];
    
    if (clickedRow != -1) {
        id item = [[self projectSourceList] itemAtRow:clickedRow];
        
        if ([item isKindOfClass:[Urls class]]) {
            [self setClickedUrl:item];
            
            for (NSMenuItem *menuItem in [menu itemArray]) {
                [menuItem setHidden:NO];
            }
        }
        else {
            for (NSMenuItem *menuItem in [menu itemArray]) {
                [menuItem setHidden:YES];
            }
        }
    }
}
@end
