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
#import "Reachability.h"
#import "FetchURLConnection.h"
#import "XMLReader.h"
#import "XmlViewerWindowController.h"
#import "PlistViewerWindowController.h"
#import "StandardPaths.h"

@interface MainWindowController ()

/**
 * @name Current Project and URL
 */
/// Backing store for headersTableView
@property (strong, nonatomic) NSMutableArray *headerDataSource;

/// Backing store for parametersTableView
@property (strong, nonatomic) NSMutableArray *paramDataSource;

/// Backing store for projectSourceList
@property (strong, nonatomic) NSMutableArray *projectList;

/// Backing store that holds all known header names
@property (strong, nonatomic) NSArray *headerNames;

/**
 * @name Current Project and URL
 */

/// The current Project
@property (strong, nonatomic) Projects *currentProject;

/// The current URl
@property (strong, nonatomic) Urls *currentUrl;

/**
 * @name Toolbar Handling
 */

/// Reference to toolbar
@property (strong, nonatomic) CNSplitViewToolbar *toolbar;

/// Reference to remove button in toolbar
@property (strong, nonatomic) CNSplitViewToolbarButton *removeButton;

/// Reference to export button in toolbar
@property (strong, nonatomic) CNSplitViewToolbarButton *exportButton;

/**
 * @name Cell Storage
 */

/// Mutable array that holds a reference to all url cells (Used for updating reachability status)
@property (strong, nonatomic) NSMutableArray *urlCellArray;

/// Mutable array that holds a reference to all project cells
@property (strong, nonatomic) NSMutableArray *projectCellArray;

/**
 * @name Booleans
 */

/// BOOL to set whether a fetch is currently occuring
@property (nonatomic) BOOL isFetching;

/// Temp property for storying the clicked URL
@property (strong, nonatomic) Urls *clickedUrl;

/// Reference to currently happening Fetch action
@property (strong, nonatomic) FetchURLConnection *fetchConnection;

/**
 *  The item currently being dragged
 */
@property (strong, nonatomic) Urls *draggedNode;

/**
 *  The parent being dragged to
 */
@property (strong, nonatomic) Projects *receivingNode;

/// Reference to the current date
@property (strong, nonatomic) NSDate *currentDate;

/// Used if the user has chosen to check reachability of URLs
@property (strong, nonatomic) NSTimer *pingTimer;

/// JSON Data returns from fetch action.  This is either an NSDictionary or NSArray
@property (strong, nonatomic) id responseData;

/**
 * @name Internal Methods
 */

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
 * @param text The text to append to the outputTextView.  Accepted NSString or NSAttributedString.
 * @param color The color to show the text in
 */
-(void)appendToOutput:(id)text color:(NSColor *)color;

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
 * @return NetworkStatus of the specified URL
 */
-(NetworkStatus)urlVerification:(NSString *)urlString;

/**
 *  Alert the user that access has been denied from the server.  A 401 has occurred.
 */
-(void)accessDenied;

@end

@implementation MainWindowController

#pragma mark
#pragma mark Lifecycle

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    NSLog(@"%s", __FUNCTION__);
    
    self = [super initWithWindowNibName:windowNibName];
    
    if (self) {
        _headerDataSource = [[NSMutableArray alloc] init];
        _paramDataSource = [[NSMutableArray alloc] init];
        _projectList = [[NSMutableArray alloc] init];
        
        _headerNames = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"HeaderNames" ofType:@"plist"]];
    }
    return self;
}

-(void)windowDidLoad
{
    NSLog(@"%s", __FUNCTION__);
    
    [super windowDidLoad];
    
    [[self logRequestCheckBox] setToolTip:@"Log the HTTP request to the output."];
    [[self customPostBodyCheckBox] setToolTip:@"Add a custom payload, usually a JSON string, to the HTTP request."];
    [[self fetchButton] setToolTip:@"Initiates the Fetch request.  Hold ⌘ while clicking to clear output."];
    [[self parseButton] setToolTip:@"Attempt to parse the returned data as one of the available datatypes."];
    [[self clearOutputButton] setToolTip:@"Clear the contents of the output."];
    
    [[self splitView] setPosition:[[[NSUserDefaults standardUserDefaults] valueForKey:kSplitViewPosition] floatValue] ofDividerAtIndex:0];
    
    [[self customPayloadTextView] setAutomaticTextReplacementEnabled:NO];
    [[self customPayloadTextView] setFont:[NSFont fontWithName:@"Andale Mono" size:12]];
    [[self customPayloadTextView] setAutomaticQuoteSubstitutionEnabled:NO];
    
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
    
    [[self projectSourceList] registerForDraggedTypes:@[NSFilenamesPboardType, NSFilesPromisePboardType, @"url"]];
    [[self projectSourceList] setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
    [[self projectSourceList] setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    
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
    
    [self splitView:[self splitView] constrainSplitPosition:[[[NSUserDefaults standardUserDefaults] valueForKey:kSplitViewPosition] floatValue] ofSubviewAt:0];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSUserDefaultsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kAddUrlNotification object:nil];
}

#pragma mark
#pragma mark Methods

- (void)setupSplitviewControls
{
    NSLog(@"%s", __FUNCTION__);
    
    [self setToolbar:[[CNSplitViewToolbar alloc] init]];
    
    NSMenu *contextMenu = [[NSMenu alloc] init];
    [contextMenu addItemWithTitle:@"Add New Project" action:@selector(addProject) keyEquivalent:[NSString string]];
    [contextMenu addItemWithTitle:@"Add New URL" action:@selector(addUrl:) keyEquivalent:[NSString string]];
    [contextMenu setDelegate:self];
    
    CNSplitViewToolbarButton *addButton = [[CNSplitViewToolbarButton alloc] initWithContextMenu:contextMenu];
    [addButton setImageTemplate:CNSplitViewToolbarButtonImageTemplateAdd];
    [addButton setToolTip:@"Add Project or URL"];
    
    _removeButton = [[CNSplitViewToolbarButton alloc] init];
    [[self removeButton] setImageTemplate:CNSplitViewToolbarButtonImageTemplateRemove];
    [[self removeButton] setTarget:self];
    [[self removeButton] setAction:@selector(removeProjectOrUrl)];
    [[self removeButton] setEnabled:NO];
    [[self removeButton] setToolTip:@"Remove Item"];
    
    _exportButton = [[CNSplitViewToolbarButton alloc] init];
    [[self exportButton] setImageTemplate:CNSplitViewToolbarButtonImageTemplateShare];
    [[self exportButton] setTarget:self];
    [[self exportButton] setAction:@selector(exportProject:)];
    [[self exportButton] setEnabled:NO];
    [[self exportButton] setToolTip:@"Export Project"];
    
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

    [[self headerSegCont] setEnabled:[[self headerDataSource] count] != 0 forSegment:1];
    [[self paramSegCont] setEnabled:[[self paramDataSource] count] != 0 forSegment:1];
}

-(void)unloadData
{
    NSLog(@"%s", __FUNCTION__);
    
    [[self parseButton] setEnabled:NO];
    [[self fetchButton] setEnabled:NO];
    [[self urlTextField] setEnabled:NO];
    [[self urlDescriptionTextField] setEnabled:NO];
    
    [[self headerDataSource] removeAllObjects];
    [[self paramDataSource] removeAllObjects];
    
    [[self headersTableView] reloadData];
    [[self parametersTableView] reloadData];
}

-(void)findInOutput
{
    [[self textFinder] performAction:NSTextFinderActionShowFindInterface];
}

#pragma mark
#pragma mark Request Logging

- (void)appendToOutput:(id)text color:(NSColor *)color
{
    NSLog(@"%s", __FUNCTION__);
    
    if (!text) {
        text = @"ERROR";
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([text isKindOfClass:[NSString class]]) {
            NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[text stringByAppendingString:@"\n"]];
            
            [attributedString addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Andale Mono" size:12] range:NSMakeRange(0, [text length])];
            
            if (color) {
                [attributedString addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, [text length])];
            }
            
            [[[self outputTextView] textStorage] appendAttributedString:attributedString];
        }
        else {
            [[[self outputTextView] textStorage] appendAttributedString:text];
        }
        
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
    
    if (![[self urlTextField] stringValue] || [[[self urlTextField] stringValue] isEqualToString:[NSString string]]) {
        return NO;
    }
    
    BOOL validPrefix = [[[self urlTextField] stringValue] hasValidURLPrefix];
    
    if (!validPrefix) {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Invalid URL"
                                              defaultButton:@"OK"
                                            alternateButton:nil
                                                otherButton:nil
                                  informativeTextWithFormat:@"The url must be prefixed with the URL type.  Valid types are http and https"];
        
        [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
        
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
    
    if ([self isFetching]) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Change URL?"
                                         defaultButton:@"Yes"
                                       alternateButton:@"Nevermind"
                                           otherButton:nil
                             informativeTextWithFormat:@"A Fetch is currently happening.  Are you sure you wish to switch urls?"];
        
        [alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
            if (response == NSModalResponseOK) {
                [[self fetchConnection] cancel];
                
                [self setIsFetching:NO];
                
                [[self fetchButton] setHidden:NO];
                [[self progressIndicator] stopAnimation:self];
                [[self progressIndicator] setHidden:YES];
                
                [self appendToOutput:@"CANCELED REQUEST" color:[[NSUserDefaults standardUserDefaults] colorForKey:kFailureColor]];
            }
        }];
    }
    
    [[self fetchButton] setEnabled:YES];
    
    Urls *tempUrl = url;
    
    [self setCurrentUrl:tempUrl];
    
    [[self methodCombo] selectItemAtIndex:[[tempUrl method] intValue]];
    [[self methodCombo] setEnabled:YES];
    
    if ([[tempUrl customPayload] hasValue]) {
        [[self customPayloadTextView] setString:[tempUrl customPayload]];
        [[self customPostBodyCheckBox] setState:NSOnState];
    }
    
    [[self urlDescriptionTextField] setStringValue:[[tempUrl urlDescription] hasValue] ? [tempUrl urlDescription] : [NSString string]];
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
    
    [[self usernameTextField] setEnabled:YES];
    [[self passwordTextField] setEnabled:YES];
    
    if ([tempUrl username]) {
        [[self usernameTextField] setStringValue:[tempUrl username]];
    }
    else {
        [[self usernameTextField] setStringValue:[NSString string]];
    }
    
    if ([tempUrl password]) {
        [[self passwordTextField] setStringValue:[tempUrl password]];
    }
    else {
        [[self passwordTextField] setStringValue:[NSString string]];
    }
}

-(void)addUrl:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
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

-(IBAction)cloneHeaders:(id)sender
{
    Urls *clickedUrl = nil;
    
    if ([[self projectSourceList] clickedRow] == kNoRowSelected) {
        clickedUrl = [self currentUrl];
    }
    else {
        clickedUrl = [[self projectSourceList] itemAtRow:[[self projectSourceList] clickedRow]];
    }
    
    if (!clickedUrl) {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Error"
                                              defaultButton:@"OK"
                                            alternateButton:nil
                                                otherButton:nil
                                  informativeTextWithFormat:@"An error has occurred.  Please try again."];
        
        [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
    }
    
    NSString *messageString = [NSString stringWithFormat:@"Are you sure you wish to clone the headers from \"%@\" to all the other URLs in this Project?", [clickedUrl urlDescription] ? [clickedUrl urlDescription] : [clickedUrl url]];
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"Clone Headers?"
                                     defaultButton:@"OK"
                                   alternateButton:nil
                                       otherButton:@"Cancel"
                         informativeTextWithFormat:messageString, nil];
    
    [alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSSet *currentHeaders = [clickedUrl headers];
            
            for (Urls *tempURL in [[self currentProject] urls]) {
                if (tempURL != clickedUrl) {
                    for (Headers *tempHeader in currentHeaders) {
                        Headers *header = [Headers create:@{kName: [tempHeader name], kValue: [tempHeader value]}];
                        
                        BOOL addHeader = YES;
                        
                        for (Headers *anotherHeader in [tempURL headers]) {
                            if ([[anotherHeader name] isEqualToString:[tempHeader name]] && [[anotherHeader value] isEqualToString:[tempHeader value]]) {
                                addHeader = NO;
                            }
                        }
                        
                        if (addHeader) {
                            [header setUrl:tempURL];
                            [header save];
                            
                            [tempURL addHeadersObject:header];
                            [tempURL save];
                        }
   
                    }
                }
            }
        }
    }];
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

-(void)loadProject:(Projects *)project
{
    NSLog(@"%s", __FUNCTION__);
    
    [[self headerDataSource] removeAllObjects];
    [[self headersTableView] reloadData];
    
    [[self paramDataSource] removeAllObjects];
    [[self parametersTableView] reloadData];
    
    [[self methodCombo] selectItemAtIndex:GET_METHOD];
    
    [[self urlTextField] setStringValue:[NSString string]];
    [[self urlDescriptionTextField] setStringValue:[NSString string]];
    
    [[self customPayloadTextView] setString:[NSString string]];
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
    NSLog(@"%s", __FUNCTION__);
    
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    
    [savePanel setTitle:@"Save Log"];
    [savePanel setNameFieldStringValue:[@"LogFile" stringByAppendingPathExtension:@"txt"]];
    
    if ([savePanel runModal] == NSOKButton) {
        NSError *error = nil;
        
        [[[self outputTextView] string] writeToFile:[[savePanel URL] path] atomically:YES encoding:NSUTF8StringEncoding error:&error];
        
        if (error) {
            NSAlert *errorAlert = [NSAlert alertWithError:error];
            
            [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
        }
    }
}

-(void)addProject
{
    NSLog(@"%s", __FUNCTION__);
    
    if (![self projectList]) {
        [self setProjectList:[[NSMutableArray alloc] init]];
    }
    
    [self unloadData];
    
    [self setCurrentUrl:nil];
    
    [[self urlDescriptionTextField] setStringValue:[NSString string]];
    [[self urlTextField] setStringValue:[NSString string]];
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
    NSLog(@"%s", __FUNCTION__);
    
    id item = [[self projectSourceList] itemAtRow:[[self projectSourceList] selectedRow]];
    
    if ([item isKindOfClass:[Projects class]]) {
        NSString *messageText = [NSString stringWithFormat:@"Delete project \"%@\"?  You cannot undo this action.", [item name]];
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"Delete Project?" defaultButton:@"Delete" alternateButton:nil otherButton:@"Cancel" informativeTextWithFormat:messageText, nil];
        
        [alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
            if (response == NSModalResponseOK) {
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
                
                [[self urlCellArray] removeAllObjects];
                [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
                [[self projectSourceList] reloadData];
            }
        }];
    }
    else if ([item isKindOfClass:[Urls class]]) {
        [self deleteURLHandler:item];
    }
}

-(void)deleteURLHandler:(Urls *)item
{
    NSString *messageText = @"Delete url? You cannot undo this action.";
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"Delete URL?" defaultButton:@"Delete" alternateButton:nil otherButton:@"Cancel" informativeTextWithFormat:messageText, nil];
    
    [alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            [item delete];
            
            if (item == [self currentUrl]) {
                [[self parseButton] setEnabled:NO];
                [[self fetchButton] setEnabled:NO];
                
                [[self urlTextField] setStringValue:[NSString string]];
                [[self urlDescriptionTextField] setStringValue:[NSString string]];
                
                [[self methodCombo] setEnabled:NO];
                
                [[self headerDataSource] removeAllObjects];
                [[self paramDataSource] removeAllObjects];
                
                [[self headersTableView] reloadData];
                [[self parametersTableView] reloadData];
                
                [[self urlCellArray] removeAllObjects];
                [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
                [[self projectSourceList] reloadData];
            }
        }
    }];
    
}
#pragma mark
#pragma mark IBActions

-(IBAction)fetchAction:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    if (([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask)) {
        [self clearOutput:nil];
    }
    
    [self setCurrentDate:[NSDate date]];
    
    [self setIsFetching:YES];
    
    [[self fetchButton] setHidden:YES];
    [[self progressIndicator] setHidden:NO];
    [[self progressIndicator] startAnimation:self];
    
    if ([[[self urlTextField] stringValue] isEqualToString:[NSString string]] || ![[self urlTextField] stringValue]) {
        NSAlert *alert = [[NSAlert alloc] init];
        
        [alert addButtonWithTitle:@"OK"];
        [alert setMessageText:@"Unable to Fetch."];
        [alert setInformativeText:@"You must specify a URL."];
        [alert setAlertStyle:NSWarningAlertStyle];
        
        [alert beginSheetModalForWindow:[self window] completionHandler:nil];
        
        [[self fetchButton] setHidden:NO];
        [[self progressIndicator] stopAnimation:self];
        [[self progressIndicator] setHidden:YES];
        
        return;
    }
    
    if ([self addToUrlListIfUnique]) {
        NSMutableString *parameters = [[NSMutableString alloc] init];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
        
        [request setHTTPMethod:[[self methodCombo] objectValueOfSelectedItem]];
        
        for (Headers *tempHeader in [self headerDataSource]) {
            [request setValue:[tempHeader value] forHTTPHeaderField:[tempHeader name]];
        }
        
        if (![[[self usernameTextField] stringValue] isEqualToString:[[self currentUrl] username]] || ![[[self passwordTextField] stringValue] isEqualToString:[[self currentUrl] password]]) {
            [[self currentUrl] setUsername:[[self usernameTextField] stringValue]];
            [[self currentUrl] setPassword:[[self passwordTextField] stringValue]];
            
            [[self currentUrl] save];
        }
                                                                                                      
        if ([[self customPostBodyCheckBox] state] == NSOnState) {
            [request setHTTPBody:[[[self customPayloadTextView] string] dataUsingEncoding:NSUTF8StringEncoding]];
            [[self currentUrl] setCustomPayload:[[self customPayloadTextView] string]];
        }
        else {
            [[self currentUrl] setCustomPayload:nil];
            
            for (Parameters *tempParam in [self paramDataSource]) {
                if (tempParam == [[self paramDataSource] first]) {
                    [parameters appendString:[NSString stringWithFormat:@"?%@=%@", [[tempParam name] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [[tempParam value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
                }
                else {
                    [parameters appendString:[NSString stringWithFormat:@"&%@=%@", [[tempParam name] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [[tempParam value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
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
        
        if ([[self currentUrl] hasChanges]) {
            [[self currentUrl] save];
        }
        
        if ([[[self currentUrl] username] length] > 0 && [[[self currentUrl] password] length] > 0) {
            NSString *authString = [NSString stringWithFormat:@"%@:%@", [[self currentUrl] username], [[self currentUrl] password]];
            NSData *authData = [authString dataUsingEncoding:NSASCIIStringEncoding];
            
            NSString *authValue = nil;
            
            if ([authData respondsToSelector:@selector(base64EncodedStringWithOptions:)]) {
                authValue = [NSString stringWithFormat:@"Basic %@", [authData base64EncodedStringWithOptions:0]];
            }
            else {
                authValue = [NSString stringWithFormat:@"Basic %@", [authData base64Encoding]];
            }
            
            [request setValue:authValue forHTTPHeaderField:@"Authorization"];
        }
        
        _fetchConnection = [FetchURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response,
                                                                                                                                      NSData *data,
                                                                                                                                      NSError *connectionError) {
            
            [self setIsFetching:NO];
            
            NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
            NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
            
            if ([urlResponse statusCode] == 401) {
                [self accessDenied];
            }
            
            NSMutableDictionary *responseDict = [[urlResponse allHeaderFields] mutableCopy];
            
            [responseDict addEntriesFromDictionary:@{@"Response Code": [NSString stringWithFormat:@"%ld", (long)[urlResponse statusCode]]}];
            
            [self setResponseDict:responseDict];
            
            [self appendToOutput:kResponseSeparator color:[userDefaults colorForKey:kSeparatorColor]];
            [self appendToOutput:[urlResponse responseString] color:[userDefaults colorForKey:[urlResponse isGoodResponse] ? kSuccessColor : kFailureColor]];
            [self appendToOutput:[NSString stringWithFormat:@"%@", [urlResponse allHeaderFields]] color:[userDefaults colorForKey:kSuccessColor]];
            
            if (!connectionError) {
                [self setResponseData:data];
                
                [[self parseButton] setEnabled:YES];
                
                if (data) {
                    id jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments|NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves error:nil];
                    
                    if (jsonData && [NSJSONSerialization isValidJSONObject:jsonData]) {
                        NSData *jsonHolder = [NSJSONSerialization dataWithJSONObject:jsonData options:NSJSONWritingPrettyPrinted error:nil];
                        
                        if (jsonHolder) {
                            [self appendToOutput:[[NSString alloc] initWithData:jsonHolder encoding:NSUTF8StringEncoding] color:[userDefaults colorForKey:kForegroundColor]];
                        }
                    }
                    else {
                        [self appendToOutput:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] color:[userDefaults colorForKey:kForegroundColor]];
                        
                        if ([[NSUserDefaults standardUserDefaults] boolForKey:kParseHtmlInOutput]) {
                            if ([[urlResponse allHeaderFields][@"Content-Type"] rangeOfString:@"text/html"].location != NSNotFound) {
                                NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:data documentAttributes:nil];
                                
                                [self appendToOutput:kParsedOutput color:[userDefaults colorForKey:kSeparatorColor]];
                                [self appendToOutput:attributedString color:nil];
                                [self appendToOutput:kParsedOutput color:[userDefaults colorForKey:kSeparatorColor]];
                            }
                        }
                    }
                    
                    if ([[[self jsonWindow] window] isVisible]) {
                        [self showJson:nil];
                    }
                }
                else {
                    [self appendToOutput:kNoResponseData color:[userDefaults colorForKey:kSuccessColor]];
                }
            }
            else {
                NSAlert *errorAlert = [NSAlert alertWithError:connectionError];
                
                [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
            }
            
            NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:[self currentDate]];
            
            timeInterval *= 1000;
            
            [self appendToOutput:[[[NSString alloc] init] formatInterval:timeInterval] color:[userDefaults colorForKey:kSuccessColor]];
            
            [[self fetchButton] setHidden:NO];
            [[self progressIndicator] stopAnimation:self];
            [[self progressIndicator] setHidden:YES];
        }];
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
        if ([[self headersTableView] selectedRow] == kNoRowSelected) {
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
        if ([[self parametersTableView] selectedRow] == kNoRowSelected) {
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
    
    [[self outputTextView] setString:[NSString string]];
    
    [[self clearOutputButton] setEnabled:NO];
}

-(IBAction)showJson:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
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
        
        [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
    }
}

-(IBAction)showCsv:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSArray *rows = [NSArray arrayWithContentsOfString:[[NSString alloc] initWithData:[self responseData] encoding:NSUTF8StringEncoding] options:CHCSVParserOptionsSanitizesFields|CHCSVParserOptionsStripsLeadingAndTrailingWhitespace];
    
    if (rows) {
        [self setCsvWindow:[[CsvViewerWindowController alloc] initWithWindowNibName:@"CsvViewerWindowController" dataSource:rows]];
        
        [[self csvWindow] setNumberOfColumns:[rows[0] count]];
        
        [[[self csvWindow] window] makeKeyAndOrderFront:self];
    }
    else {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Error"
                                              defaultButton:@"OK"
                                            alternateButton:nil
                                                otherButton:nil
                                  informativeTextWithFormat:@"The data is not in the correct format."];
        
        [errorAlert setAlertStyle:NSCriticalAlertStyle];
        [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
    }
}

-(IBAction)showXml:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSError *parseError = nil;
    NSDictionary *xmlDictionary = [XMLReader dictionaryForXMLData:[self responseData] error:&parseError];
    
    if (xmlDictionary) {
        if (![self xmlWindow]) {
            [self setXmlWindow:[[XmlViewerWindowController alloc] initWithWindowNibName:@"XmlViewerWindowController" xml:xmlDictionary]];
        }
        else {
            [[self xmlWindow] setXmlData:xmlDictionary];
            [[[self xmlWindow] outlineView] reloadData];
        }
        
        [[[self xmlWindow] window] makeKeyAndOrderFront:self];
    }
    else {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Error"
                                              defaultButton:@"OK"
                                            alternateButton:nil
                                                otherButton:nil
                                  informativeTextWithFormat:@"The data is not in the correct format."];
        
        [errorAlert setAlertStyle:NSCriticalAlertStyle];
        [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
    }
}

-(IBAction)showPlist:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    NSString *errorDescription = nil;
    NSPropertyListFormat format;
    NSDictionary *plistDictionary = [NSPropertyListSerialization propertyListFromData:[self responseData] mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&errorDescription];
    
    if (plistDictionary) {
        if (![self plistWindow]) {
            [self setPlistWindow:[[PlistViewerWindowController alloc] initWithWindowNibName:@"PlistViewerWindowController" plist:plistDictionary]];
        }
        else {
            [[self plistWindow] setPlistData:plistDictionary];
            [[[self plistWindow] outlineView] reloadData];
        }
        
        [[[self plistWindow] window] makeKeyAndOrderFront:self];
    }
    else {
        NSAlert *errorAlert = [NSAlert alertWithMessageText:@"Error"
                                              defaultButton:@"OK"
                                            alternateButton:nil
                                                otherButton:nil
                                  informativeTextWithFormat:@"The data is not in the correct format."];
        
        [errorAlert setAlertStyle:NSCriticalAlertStyle];
        [errorAlert beginSheetModalForWindow:[self window] completionHandler:nil];
    }
}

-(IBAction)duplicateURL:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    @try {
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
        [duplicateUrl setUsername:[oldUrl username]];
        [duplicateUrl setPassword:[oldUrl password]];
        
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
    @catch (NSException *exception) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                         defaultButton:@"OK"
                                       alternateButton:nil
                                           otherButton:nil
                             informativeTextWithFormat:@"There was an error duplicating the URL."];
        
        [alert beginSheetModalForWindow:[self window] completionHandler:nil];
    }
}

-(IBAction)parseAction:(id)sender
{
    [NSMenu popUpContextMenu:[self parseMenu] withEvent:[[NSApplication sharedApplication] currentEvent] forView:sender];
}

-(IBAction)renameProject:(id)sender
{
    NSLog(@"%s", __FUNCTION__);
    
    ProjectCell *cell = [[self projectSourceList] viewAtColumn:0 row:[[self projectSourceList] clickedRow] makeIfNecessary:NO];
    
    NSTextField *textField = [cell textField];
    
    [textField setEditable:YES];
    
    [[self projectSourceList] editColumn:0 row:[[self projectSourceList] clickedRow] withEvent:nil select:YES];
}

-(IBAction)deleteURLAction:(id)sender
{
    id item = [[self projectSourceList] itemAtRow:[[self projectSourceList] selectedRow]];
    
    [self deleteURLHandler:item];
}

#pragma mark
#pragma mark NSControlTextDelegate

- (void)controlTextDidChange:(NSNotification *)notification
{
    NSLog(@"%s", __FUNCTION__);
    
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
    else if ([notification object] == [self usernameTextField]) {
        if ([[[self usernameTextField] stringValue] length] > 0) {
            if ([self currentUrl]) {
                [[self currentUrl] setUsername:[[self usernameTextField] stringValue]];
                [[self currentUrl] save];
            }
        }
    }
    else if ([notification object] == [self passwordTextField]) {
        if ([[[self passwordTextField] stringValue] length] > 0) {
            if ([self currentUrl]) {
                [[self currentUrl] setPassword:[[self passwordTextField] stringValue]];
                [[self currentUrl] save];
            }
        }
    }
}

-(void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSLog(@"%s", __FUNCTION__);
    
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
        
        NSTextField *textField = [notification object];
        
        [textField setEditable:NO];
    }
}

-(void)textDidEndEditing:(NSNotification *)notification
{
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
    return YES;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    NSLog(@"%s", __FUNCTION__);
    
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
    NSLog(@"%s", __FUNCTION__);
    
    static NSString *const CellIdentifier = @"DataCell";
    static NSString *const UrlCellIdentifier = @"UrlCell";
    
    if ([item isKindOfClass:[Projects class]]) {
        if (![self projectCellArray]) {
            [self setProjectCellArray:[NSMutableArray array]];
        }
        
        ProjectCell *cell = [outlineView makeViewWithIdentifier:CellIdentifier owner:self];
        
        Projects *tempProject = item;
        
        [[cell textField] setStringValue:[tempProject name]];
        [cell setProject:tempProject];
        
        [[cell addUrlButton] setHidden:NO];
        
        [[self projectCellArray] addObject:cell];
        
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
    NSLog(@"%s", __FUNCTION__);
    
    Projects *tempProject = item;
    
    [tempProject setName:object];
    
    [tempProject save];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification;
{
    NSLog(@"%s", __FUNCTION__);
    
    Projects *project = [notification userInfo][@"NSObject"];
    
    [project setExpanded:@YES];
    [project save];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    NSLog(@"%s", __FUNCTION__);
    
    Projects *project = [notification userInfo][@"NSObject"];
    
    [project setExpanded:@NO];
    [project save];
}

-(void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    NSLog(@"%s", __FUNCTION__);
    
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
            [[self urlTextField] setStringValue:[NSString string]];
        }
        
        [self loadUrl:tempItem];
    }
}

#pragma mark
#pragma mark NSOutlineViewDelegate Drag Support

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    NSLog(@"%s", __FUNCTION__);
    
    id tempProject = item;
    
    if (tempProject && [tempProject isKindOfClass:[Projects class]]) {
        if ([[tempProject name] isEqualToString:[[_draggedNode project] name]]) {
            return NSDragOperationNone;
        }
        
        [self setReceivingNode:tempProject];
    }
    else if ([tempProject isKindOfClass:[Urls class]]) {
        tempProject = [tempProject project];
        
        [self setReceivingNode:tempProject];
    }
    
    
    return NSDragOperationGeneric;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    NSLog(@"%s", __FUNCTION__);
    
    NSPasteboard *pasteboard = [info draggingPasteboard];
    
    NSArray *urls = [pasteboard readObjectsForClasses:@[[NSURL class]] options:0];
    
    if ([urls count] != 0) {
        for (NSURL *url in urls) {
            if ([ProjectHandler importFromPath:[url path]]) {
                [[self projectList] removeAllObjects];
                
                [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
                
                [[self urlCellArray] removeAllObjects];
                
                [[self projectSourceList] reloadData];
            }
        }
    }
    else {
        if ([[self receivingNode] isKindOfClass:[Urls class]]) {
            return NO;
        }
        
        Urls *tempUrl = _draggedNode;
        
        if (tempUrl) {
            if ([self receivingNode]) {
                [tempUrl setProject:[self receivingNode]];
                [tempUrl save];
                
                [self setProjectList:[[[Projects all] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]] mutableCopy]];
                [[self projectSourceList] reloadData];
            }
        }
        else {
            NSLog(@"Unable to finish drag");
            
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard
{
    NSLog(@"%s", __FUNCTION__);
    
    if ([items[0] isKindOfClass:[Urls class]]) {
        [pasteboard declareTypes:@[@"url"] owner:nil];
        _draggedNode = [items objectAtIndex:0];
        
        return YES;
    }
    else if ([items[0] isKindOfClass:[Projects class]]) {
        NSString *filePath = [[NSFileManager defaultManager] pathForTemporaryFile:[NSString stringWithFormat:@"%@.fetch", [items[0] name]]];
        
        [pasteboard declareTypes:@[NSFilesPromisePboardType] owner:nil];
        [pasteboard setPropertyList:@[[filePath pathExtension]] forType:NSFilesPromisePboardType];
        
        return YES;
    }
    return NO;
}

- (NSArray *)outlineView:(NSOutlineView *)outlineView namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination forDraggedItems:(NSArray *)items
{
    NSLog(@"%s", __FUNCTION__);
    
    [[NSFileManager defaultManager] createDirectoryAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"/fetchTemp/"]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *sourceFilePath = [[NSFileManager defaultManager] pathForTemporaryFile:[NSString stringWithFormat:@"/fetchTemp/%@.fetch", [items[0] name]]];
    
    [ProjectHandler exportProject:(Projects *)items[0] toUrl:[NSURL fileURLWithPath:sourceFilePath]];
    
    NSError *error = nil;
    
    [[NSFileManager defaultManager] moveItemAtPath:sourceFilePath
                                            toPath:[[dropDestination path] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.fetch", [items[0] name]]] error:&error];
    
    if (error) {
        NSAlert *alert = [NSAlert alertWithError:error];
        
        [alert beginSheetModalForWindow:[self window] completionHandler:nil];
        
    }
    
    return @[[sourceFilePath lastPathComponent]];
}

#pragma mark
#pragma mark CNSplitViewToolbarDelegate

- (NSUInteger)toolbarAttachedSubviewIndex:(CNSplitViewToolbar *)theToolbar
{
    NSLog(@"%s", __FUNCTION__);
    
    return kProjectListSplitViewSide;
}

#pragma mark
#pragma mark NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    NSLog(@"%s", __FUNCTION__);
    
    return kMinimumSplitViewSize;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex
{
    NSLog(@"%s", __FUNCTION__);
    
    BOOL shouldHideStatusImages = NO;
    
    for (UrlCell *cell in [self urlCellArray]) {
        NSRect statusRect = [[cell statusImage] frame];
        CGSize sizeOfText = [[[cell textField] stringValue] sizeWithAttributes:@{NSFontNameAttribute: [[cell textField] font]}];
        
        NSRect textBoxRect = NSMakeRect(cell.textField.frame.origin.x, cell.textField.frame.origin.y, sizeOfText.width, sizeOfText.height);
        
        if (NSIntersectsRect(statusRect, textBoxRect)) {
            shouldHideStatusImages = YES;
            
            break;
        }
    }
    
    if (shouldHideStatusImages) {
        for (UrlCell *cell in [self urlCellArray]) {
            [[[cell statusImage] animator] setAlphaValue:0.0];
        }
        
        for (ProjectCell *cell in [self projectCellArray]) {
            [[[cell addUrlButton] animator] setAlphaValue:0.0];
        }
    }
    else {
        for (UrlCell *cell in [self urlCellArray]) {
            [[[cell statusImage] animator] setAlphaValue:1.0];
        }
        
        for (ProjectCell *cell in [self projectCellArray]) {
            [[[cell addUrlButton] animator] setAlphaValue:1.0];
        }
        
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:@(proposedPosition) forKey:kSplitViewPosition];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    return proposedPosition;
}

#pragma mark
#pragma mark UrlCell Handlers

-(void)createTimerWithTimeInterval:(NSTimeInterval)timeInterval
{
    NSLog(@"%s", __FUNCTION__);
    
    _pingTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval block:^{
        
        for (UrlCell *cell in [self urlCellArray]) {
            __block __weak UrlCell *tempCell = cell;
            
            if (![[[tempCell currentUrl] url] isEqualToString:[NSString string]]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    NetworkStatus status = [self urlVerification:[[tempCell currentUrl] url]];
                    
                    if (status != NotReachable) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[tempCell statusImage] setImage:[NSImage imageNamed:NSImageNameStatusAvailable]];
                            
                            [[tempCell currentUrl] setSiteStatus:NSImageNameStatusAvailable];
                            [[tempCell currentUrl] save];
                        });
                    }
                    else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[tempCell statusImage] setImage:[NSImage imageNamed:NSImageNameStatusUnavailable]];
                            
                            [[tempCell currentUrl] setSiteStatus:NSImageNameStatusUnavailable];
                            [[tempCell currentUrl] save];
                        });
                    }
                });
            }
        }
    } repeats:YES];
}

-(NetworkStatus)urlVerification:(NSString *)urlString
{
    NSLog(@"%s", __FUNCTION__);
    
    NSURL *url = [NSURL URLWithString:urlString];
    
    Reachability *reachability = [Reachability reachabilityWithHostname:[url host]];
    
    NetworkStatus status = [reachability currentReachabilityStatus];
    
    return status;
}

-(void)accessDenied
{
    NSLog(@"%s", __FUNCTION__);

    NSAlert *accessDeniedAlert = [NSAlert alertWithMessageText:@"Access Denied"
                                                 defaultButton:@"OK"
                                               alternateButton:nil
                                                   otherButton:nil
                                     informativeTextWithFormat:@"The server has returned a status code of 401.  This usually means that your authorization username or password is incorrect."];
    
    [accessDeniedAlert beginSheetModalForWindow:[self window] completionHandler:nil];
}

#pragma mark -
#pragma mark NSMenuDelegate

-(void)menuNeedsUpdate:(NSMenu *)menu
{
    NSLog(@"%s", __FUNCTION__);
    
    NSInteger clickedRow = [[self projectSourceList] clickedRow];
    
    if (clickedRow != kNoRowSelected) {
        id item = [[self projectSourceList] itemAtRow:clickedRow];
        
        if ([item isKindOfClass:[Urls class]]) {
            [self setClickedUrl:item];
            
            [[menu itemAtIndex:0] setHidden:NO];
            [[menu itemAtIndex:1] setHidden:NO];
            [[menu itemAtIndex:2] setHidden:NO];
            [[menu itemAtIndex:3] setHidden:YES];
            [[menu itemAtIndex:4] setHidden:NO];
            [[menu itemAtIndex:5] setHidden:NO];
        }
        else {
            [[menu itemAtIndex:0] setHidden:YES];
            [[menu itemAtIndex:1] setHidden:YES];
            [[menu itemAtIndex:2] setHidden:YES];
            [[menu itemAtIndex:3] setHidden:NO];
            [[menu itemAtIndex:4] setHidden:YES];
            [[menu itemAtIndex:5] setHidden:YES];
        }
    }
}

@end
