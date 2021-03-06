//
//  Backendless.m
//  backendlessAPI
/*
 * *********************************************************************************************************************
 *
 *  BACKENDLESS.COM CONFIDENTIAL
 *
 *  ********************************************************************************************************************
 *
 *  Copyright 2018 BACKENDLESS.COM. All Rights Reserved.
 *
 *  NOTICE: All information contained herein is, and remains the property of Backendless.com and its suppliers,
 *  if any. The intellectual and technical concepts contained herein are proprietary to Backendless.com and its
 *  suppliers and may be covered by U.S. and Foreign Patents, patents in process, and are protected by trade secret
 *  or copyright law. Dissemination of this information or reproduction of this material is strictly forbidden
 *  unless prior written permission is obtained from Backendless.com.
 *
 *  ********************************************************************************************************************
 */

#import <mach/mach.h>
#import <sys/sysctl.h>
#import "Backendless.h"
#import "Invoker.h"
#import "BackendlessCache.h"

#import <TargetConditionals.h>

#define MISSING_SERVER_URL @"Missing server URL. You should set hostURL property"
#define MISSING_APP_ID @"Missing application ID argument. Login to Backendless Console, select your app and get the ID and key from the Manage > App Settings screen. Copy/paste the values into the [backendless initApp:APIKey:]"
#define MISSING_API_KEY @"Missing API key argument. Login to Backendless Console, select your app and get the ID and key from the Manage > App Settings screen. Copy/paste the values into the [backendless initApp:APIKey:]"
#define _RANDOM_MAX_LENGTH 4000

static NSString *BACKENDLESS_HOST_URL = @"https://api.backendless.com";
static NSString *APP_TYPE = @"IOS";

@implementation Backendless

@synthesize hostURL = _hostURL, appID = _appID, apiKey = _apiKey, userService = _userService, persistenceService = _persistenceService, messagingService = _messagingService, geoService = _geoService, fileService = _fileService, customService = _customService, events = _events, cache = _cache, counters = _counters, logging = _logging, data = _data, geo = _geo, messaging = _messaging, file = _file, rt = _rt;

+(Backendless *)sharedInstance {
    static Backendless *sharedBackendless;
    @synchronized(self) {
        if (!sharedBackendless)
            sharedBackendless = [Backendless new];
    }
    return sharedBackendless;
}

-(id)init {
    if (self = [super init]) {
        _hostURL = [BACKENDLESS_HOST_URL retain];
        _appID = nil;
        _apiKey = nil;
        _headers = [NSMutableDictionary new];
    }
    return self;
}

-(void)dealloc {
    [DebLog logN:@"DEALLOC Backendless"];
    [_hostURL release];
    [_headers removeAllObjects];
    [_headers release];
    [_appConf release];
    [_userService release];
    [_persistenceService release];
    [_geoService release];
    [_messagingService release];
    [_fileService release];
    [_customService release];
    [_events release];
    [_cache release];
    [_counters release];
    [_logging release];
    [_rt release];
    [super dealloc];
}

-(UserService *)userService {
    if (!_userService) {
        _userService = [UserService new];
        [_userService getPersistentUser];
    }
    return _userService;
}

-(PersistenceService *)persistenceService {
    if (!_persistenceService) {
        _persistenceService = [PersistenceService new];
        _data = _persistenceService;
    }
    return _persistenceService;
}

-(PersistenceService *)data {
    if (!_persistenceService) {
        _persistenceService = [PersistenceService new];
        _data = _persistenceService;
        
    }
    return _data;
}

-(MessagingService *)messagingService {
    if (!_messagingService) {
        _messagingService = [MessagingService new];
        _messaging = _messagingService;
    }
    return _messagingService;
}

-(MessagingService *)messaging {
    if (!_messagingService) {
        _messagingService = [MessagingService new];
        _messaging = _messagingService;
    }
    return _messaging;
}

-(GeoService *)geoService {
    if (!_geoService) {
        _geoService = [GeoService new];
        _geo = _geoService;
    }
    return _geoService;
}

-(GeoService *)geo {
    if (!_geoService) {
        _geoService = [GeoService new];
        _geo = _geoService;
    }
    return _geo;
}

-(FileService *)fileService {
    if (!_fileService) {
        _fileService = [FileService new];
        _file = _fileService;
    }
    return _fileService;
}

-(FileService *)file {
    if (!_fileService) {
        _fileService = [FileService new];
        _file = _fileService;
    }
    return _file;
}

-(CustomService *)customService {
    if (!_customService) {
        _customService = [CustomService new];
    }
    return _customService;
}

-(Events *)events {
    if (!_events) {
        _events = [Events new];
    }
    return _events;
}

-(CacheService *)cache {
    if (!_cache) {
        _cache = [CacheService new];
    }
    return _cache;
}

-(AtomicCounters *)counters {
    if (!_counters) {
        _counters = [AtomicCounters new];
    }
    return _counters;
}

-(Logging *)logging {
    if (!_logging) {
        _logging = [Logging new];
    }
    return _logging;
}

-(RTService *)rt {
    if (!_rt) {
        _rt = [RTService new];
    }
    return _rt;
}

-(SharedObject *)sharedObject {
    return [SharedObject alloc];
}

#pragma mark -
#pragma mark getters / setters

-(NSString *)getHostUrl {
    return _hostURL;
}

-(void)setHostUrl:(NSString *)hostURL {
    if ([_hostURL isEqualToString:hostURL])
        return;
    [_hostURL release];
    _hostURL = [hostURL retain];
    [invoker setup];
}

-(NSString *)getAppId {
    return _appID;
}

-(void)setAppId:(NSString *)appID {
    if ([_appID isEqualToString:appID])
        return;
    [_appID release];
    _appID = [appID retain];
    [invoker setup];
}

-(NSString *)getAPIKey {
    return _apiKey;
}

-(void)setAPIKey:(NSString *)apiKey {
    if ([_apiKey isEqualToString:apiKey])
        return;
    [_apiKey release];
    _apiKey = [apiKey retain];
    [invoker setup];
}

-(void)initApp:(NSString *)applicationId APIKey:(NSString *)apiKey {
    [__types makeSwiftClassPrefix:[NSThread callStackSymbols][1]];
    [_appID release];
    _appID = [applicationId retain];
    [_apiKey release];
    _apiKey = [apiKey retain];
    BOOL isStayLoggedIn = backendless.userService.isStayLoggedIn;
    [DebLog log:@"Backendless -> initApp: isStayLoggedIn = %@\ncurrentUser = %@\nheaders = \n%@", isStayLoggedIn?@"YES":@"NO", backendless.userService.currentUser, _headers];
    [invoker setup];
}

-(void)initApp:(NSString *)plist {
    NSString *dataPath = [[NSBundle bundleForClass:[self class]] pathForResource:plist ofType:@"plist"];
    _appConf = (dataPath) ? [[NSDictionary dictionaryWithContentsOfFile:dataPath] retain] : nil;
    if (!self.appConf) {
        [DebLog log:@"Backendless -> initApp: file '%@.plist' is not found", plist];
        return;
    }
    [DebLog setIsActive:[_appConf[BACKENDLESS_DEBLOG_ON] boolValue]];
    [backendless initApp:_appConf[BACKENDLESS_APP_ID] APIKey:_appConf[BACKENDLESS_API_KEY]];
}

-(void)initApp {
    [self initApp:BACKENDLESS_APP_CONF];
}

-(void)initAppFault {
    NSString *value;
    if (!(value = [self getHostUrl]) || !value.length)
        [self throwFault:[Fault fault:MISSING_SERVER_URL faultCode:@"0001"]];
    else if (!(value = [self getAppId]) || !value.length)
        [self throwFault:[Fault fault:MISSING_APP_ID faultCode:@"0002"]];
    else if (!(value = [self getAPIKey]) || !value.length)
        [self throwFault:[Fault fault:MISSING_API_KEY faultCode:@"0003"]];
}

-(void)setThrowException:(BOOL)needThrow {
    invoker.throwException = needThrow;
}

-(id)throwFault:(Fault *)fault {
    if (invoker.throwException)
        @throw fault;
    return fault;
}

-(NSString *)GUIDString {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    return [(NSString *)string autorelease];
}

// Generates a random string of up to 4000 characters in length. Generates a random length up to 4000 if numCharacters is set to 0
-(NSString *)randomString:(int)numCharacters {
    static char const possibleChars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    int len = (numCharacters > _RANDOM_MAX_LENGTH || numCharacters == 0)? (int)rand() % (_RANDOM_MAX_LENGTH) : numCharacters;
    unichar characters[len];
    for (int i = 0; i < len; ++i) {
        characters[i] = possibleChars[arc4random_uniform(sizeof(possibleChars)-1)];
    }
    return [NSString stringWithCharacters:characters length:len] ;
}

-(NSString *)applicationType {
    return APP_TYPE;
}

-(void)clearAllCache {
    [backendlessCache clearAllCache];
}

-(void)clearCacheForClassName:(NSString *)className query:(id)query {
    [backendlessCache clearCacheForClassName:className query:query];
}

-(BOOL)hasResultForClassName:(NSString *)className query:(id)query {
    return [backendlessCache hasResultForClassName:className query:query];
}

-(void)setCachePolicy:(BackendlessCachePolicy *)policy {
    [backendlessCache setCachePolicy:policy];
}

-(void)setCacheStoredType:(BackendlessCacheStoredEnum)storedType {
    if (backendlessCache.storedType.integerValue == BackendlessCacheStoredDisc) {
        [backendlessCache saveOnDisc];
    }
    [backendlessCache storedType:storedType];
}

-(void)saveCache {
    if (backendlessCache.storedType.integerValue == BackendlessCacheStoredDisc) {
        [backendlessCache saveOnDisc];
    }
}

#pragma mark - hardware

-(BOOL)is64bitSimulator {
    BOOL is64bitSimulator = NO;
    
#if TARGET_OS_SIMULATOR
    /* Setting up the mib (Management Information Base) which is an array of integers where each
     * integer specifies how the data will be gathered.  Here we are setting the MIB
     * block to lookup the information on all the BSD processes on the system.  Also note that
     * every regular application has a recognized BSD process accociated with it.  We pass
     * CTL_KERN, KERN_PROC, KERN_PROC_ALL to sysctl as the MIB to get back a BSD structure with
     * all BSD process information for all processes in it (including BSD process names)
     */
    int mib[6] = {0,0,0,0,0,0};
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_ALL;
    long numberOfRunningProcesses = 0;
    struct kinfo_proc* BSDProcessInformationStructure = NULL;
    size_t sizeOfBufferRequired = 0;
    /* Here we have a loop set up where we keep calling sysctl until we finally get an unrecoverable error
     * (and we return) or we finally get a succesful result.  Note with how dynamic the process list can
     * be you can expect to have a failure here and there since the process list can change between
     * getting the size of buffer required and the actually filling that buffer.
     */
    BOOL successfullyGotProcessInformation = NO;
    int error = 0;
    while (successfullyGotProcessInformation == NO) {
        /* Now that we have the MIB for looking up process information we will pass it to sysctl to get the
         * information we want on BSD processes.  However, before we do this we must know the size of the buffer to
         * allocate to accomidate the return value.  We can get the size of the data to allocate also using the
         * sysctl command.  In this case we call sysctl with the proper arguments but specify no return buffer
         * specified (null buffer).  This is a special case which causes sysctl to return the size of buffer required.
         *
         * First Argument: The MIB which is really just an array of integers.  Each integer is a constant
         *     representing what information to gather from the system.  Check out the man page to know what
         *     constants sysctl will work with.  Here of course we pass our MIB block which was passed to us.
         * Second Argument: The number of constants in the MIB (array of integers).  In this case there are three.
         * Third Argument: The output buffer where the return value from sysctl will be stored.  In this case
         *     we don't want anything return yet since we don't yet know the size of buffer needed.  Thus we will
         *     pass null for the buffer to begin with.
         * Forth Argument: The size of the output buffer required.  Since the buffer itself is null we can just
         *     get the buffer size needed back from this call.
         * Fifth Argument: The new value we want the system data to have.  Here we don't want to set any system
         *     information we only want to gather it.  Thus, we pass null as the buffer so sysctl knows that
         *     we have no desire to set the value.
         * Sixth Argument: The length of the buffer containing new information (argument five).  In this case
         *     argument five was null since we didn't want to set the system value.  Thus, the size of the buffer
         *     is zero or NULL.
         * Return Value: a return value indicating success or failure.  Actually, sysctl will either return
         *     zero on no error and -1 on error.  The errno UNIX variable will be set on error.
         */
        error = sysctl(mib, 3, NULL, &sizeOfBufferRequired, NULL, 0);
        if (error)
            return NO;
        /* Now we successful obtained the size of the buffer required for the sysctl call.  This is stored in the
         * SizeOfBufferRequired variable.  We will malloc a buffer of that size to hold the sysctl result.
         */
        BSDProcessInformationStructure = (struct kinfo_proc*) malloc(sizeOfBufferRequired);
        if (BSDProcessInformationStructure == NULL)
            return NO;
        /* Now we have the buffer of the correct size to hold the result we can now call sysctl
         * and get the process information.
         *
         * First Argument: The MIB for gathering information on running BSD processes.  The MIB is really
         *     just an array of integers.  Each integer is a constant representing what information to
         *     gather from the system.  Check out the man page to know what constants sysctl will work with.
         * Second Argument: The number of constants in the MIB (array of integers).  In this case there are three.
         * Third Argument: The output buffer where the return value from sysctl will be stored.  This is the buffer
         *     which we allocated specifically for this purpose.
         * Forth Argument: The size of the output buffer (argument three).  In this case its the size of the
         *     buffer we already allocated.
         * Fifth Argument: The buffer containing the value to set the system value to.  In this case we don't
         *     want to set any system information we only want to gather it.  Thus, we pass null as the buffer
         *     so sysctl knows that we have no desire to set the value.
         * Sixth Argument: The length of the buffer containing new information (argument five).  In this case
         *     argument five was null since we didn't want to set the system value.  Thus, the size of the buffer
         *     is zero or NULL.
         * Return Value: a return value indicating success or failure.  Actually, sysctl will either return
         *     zero on no error and -1 on error.  The errno UNIX variable will be set on error.
         */
        error = sysctl(mib, 3, BSDProcessInformationStructure, &sizeOfBufferRequired, NULL, 0);
        if (error == 0) {
            //Here we successfully got the process information.  Thus set the variable to end this sysctl calling loop
            successfullyGotProcessInformation = YES;
        }
        else {
            /* failed getting process information we will try again next time around the loop.  Note this is caused
             * by the fact the process list changed between getting the size of the buffer and actually filling
             * the buffer (something which will happen from time to time since the process list is dynamic).
             * Anyways, the attempted sysctl call failed.  We will now begin again by freeing up the allocated
             * buffer and starting again at the beginning of the loop.
             */
            free(BSDProcessInformationStructure);
        }
    } //end while loop
    /* Now that we have the BSD structure describing the running processes we will parse it for the desired
     * process name.  First we will the number of running processes.  We can determine
     * the number of processes running because there is a kinfo_proc structure for each process.
     */
    numberOfRunningProcesses = sizeOfBufferRequired / sizeof(struct kinfo_proc);
    for (int i = 0; i < numberOfRunningProcesses; i++) {
        //Getting name of process we are examining
        const char *name = BSDProcessInformationStructure[i].kp_proc.p_comm;
        if (strcmp(name, "SimulatorBridge") == 0) {
            int p_flag = BSDProcessInformationStructure[i].kp_proc.p_flag;
            is64bitSimulator = (p_flag & P_LP64) == P_LP64;
            break;
        }
    }
    free(BSDProcessInformationStructure);
#endif
    return is64bitSimulator;
}

-(BOOL)is64bitHardware {
#if __LP64__
    // The app has been compiled for 64-bit intel and runs as 64-bit intel
    return YES;
#endif
    // Use some static variables to avoid performing the tasks several times.
    static BOOL sHardwareChecked = NO;
    static BOOL sIs64bitHardware = NO;
    if (!sHardwareChecked) {
        sHardwareChecked = YES;
#if TARGET_OS_SIMULATOR
        // The app was compiled as 32-bit for the iOS Simulator.
        // We check if the Simulator is a 32-bit or 64-bit simulator using the function is64bitSimulator()
        // See http://blog.timac.org/?p=886
        sIs64bitHardware = [self is64bitSimulator]; // is64bitSimulator();
#elif !TARGET_OS_WATCH && !TARGET_OS_TV
        // The app runs on a real iOS device: ask the kernel for the host info.
        struct host_basic_info host_basic_info;
        unsigned int count;
        kern_return_t returnValue = host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)(&host_basic_info), &count);
        if (returnValue != KERN_SUCCESS) {
            sIs64bitHardware = NO;
        }
        sIs64bitHardware = (host_basic_info.cpu_type == CPU_TYPE_ARM64);
#endif
    }
    return sIs64bitHardware;
}

@end
