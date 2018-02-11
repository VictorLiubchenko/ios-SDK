//
//  PersistenceService.m
//  backendlessAPI
/*
 * *********************************************************************************************************************
 *
 *  BACKENDLESS.COM CONFIDENTIAL
 *
 *  ********************************************************************************************************************
 *
 *  Copyright 2012 BACKENDLESS.COM. All Rights Reserved.
 *
 *  NOTICE: All information contained herein is, and remains the property of Backendless.com and its suppliers,
 *  if any. The intellectual and technical concepts contained herein are proprietary to Backendless.com and its
 *  suppliers and may be covered by U.S. and Foreign Patents, patents in process, and are protected by trade secret
 *  or copyright law. Dissemination of this information or reproduction of this material is strictly forbidden
 *  unless prior written permission is obtained from Backendless.com.
 *
 *  ********************************************************************************************************************
 */

#import "PersistenceService.h"
#import <objc/runtime.h>
#import "DEBUG.h"
#import "Types.h"
#import "Responder.h"
#import "HashMap.h"
#import "ClassCastException.h"
#import "Backendless.h"
#import "Invoker.h"
#import "ObjectProperty.h"
#import "QueryOptions.h"
#import "BackendlessEntity.h"
#import "DataStoreFactory.h"
#import "BackendlessCache.h"
#import "ObjectProperty.h"
#import "LoadRelationsQueryBuilder.h"
#import "MapDrivenDataStore.h"
#import "DefaultAdapter.h"
#import "DeviceRegistrationAdapter.h"

#define FAULT_NO_ENTITY [Fault fault:@"Entity is missing or null" detail:@"Entity is missing or null" faultCode:@"1900"]
#define FAULT_OBJECT_ID_IS_NOT_EXIST [Fault fault:@"objectId is missing or null" detail:@"objectId is missing or null" faultCode:@"1901"]
#define FAULT_NAME_IS_NULL [Fault fault:@"Name is missing or null" detail:@"Name is missing or null" faultCode:@"1902"]
#define FAULT_FIELD_IS_NULL [Fault fault:@"Field is missing or null" detail:@"Field is missing or null" faultCode:@"1903"]

// SERVICE NAME
static NSString *SERVER_PERSISTENCE_SERVICE_PATH  = @"com.backendless.services.persistence.PersistenceService";
// METHOD NAMES
static NSString *METHOD_CREATE = @"create";
static NSString *METHOD_UPDATE = @"update";
static NSString *METHOD_SAVE = @"save";
static NSString *METHOD_REMOVE = @"remove";
static NSString *METHOD_FIND = @"find";
static NSString *METHOD_FINDBYID = @"findById";
static NSString *METHOD_LOAD = @"loadRelations";
static NSString *METHOD_CALL_STORED_PROCEDURE = @"callStoredProcedure";
static NSString *METHOD_COUNT = @"count";
static NSString *METHOD_FIRST = @"first";
static NSString *METHOD_LAST = @"last";
static NSString *DELETE_RELATION = @"deleteRelation";
static NSString *LOAD_RELATION = @"loadRelations";
static NSString *CREATE_RELATION = @"setRelation";
static NSString *ADD_RELATION = @"addRelation";
static NSString *UPDATE_BULK = @"updateBulk";
static NSString *REMOVE_BULK = @"removeBulk";

@interface PersistenceService()
-(NSDictionary *)filteringProperty:(id)object;
-(BOOL)prepareClass:(Class)className;
-(BOOL)prepareObject:(id)object;
-(NSString *)typeClassName:(Class)entity;
-(NSString *)objectClassName:(id)object;
-(NSDictionary *)propertyDictionary:(id)object;
-(id)propertyObject:(id)object;
-(id)setRelations:(NSArray *)relations object:(id)object response:(id)response;
// callbacks
-(id)loadRelations:(ResponseContext *)response;
-(id)createResponse:(ResponseContext *)response;
@end

@implementation BackendlessUser (AMF)

-(id)onAMFSerialize {
    // as dictionary with '___class' label (analog of Android implementation)
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:[self getProperties]];
    data[@"___class"] = @"Users";
    [data removeObjectsForKeys:@[BACKENDLESS_USER_TOKEN, BACKENDLESS_USER_REGISTERED]];
    [DebLog log:@"BackendlessUser -> onAMFSerialize: %@", data];
    return data;
}

// overrided method MUST return 'self' to avoid a deserialization breaking
-(id)onAMFDeserialize {
    NSDictionary *props = [Types propertyDictionary:self];
    [self setProperties:props];
    [DebLog log:@"BackendlessUser -> onAMFDeserialize: %@", props];
    return self;
}

@end

@implementation NSArray (AMF)

-(id)onAMFSerialize {
    if ((self.count > 2) && [self[2] isKindOfClass:[NSString class]]) {
        if ([self[2] isEqualToString:NSStringFromClass([BackendlessUser class])]) {
            NSMutableArray *data = [NSMutableArray arrayWithArray:self];
            data[2] = @"Users";
            return data;
        }
    }
    return self;
}

@end

@implementation PersistenceService

-(id)init {
    if (self = [super init]) {
        [[Types sharedInstance] addClientClassMapping:@"com.backendless.services.persistence.NSArray" mapped:[NSArray class]];
        [[Types sharedInstance] addClientClassMapping:@"com.backendless.services.persistence.ObjectProperty" mapped:[ObjectProperty class]];
        [[Types sharedInstance] addClientClassMapping:@"com.backendless.services.persistence.QueryOptions" mapped:[QueryOptions class]];
        [[Types sharedInstance] addClientClassMapping:@"com.backendless.geo.model.GeoPoint" mapped:[GeoPoint class]];
        [[Types sharedInstance] addClientClassMapping:@"java.lang.ClassCastException" mapped:[ClassCastException class]];
        _permissions = [DataPermission new];
    }
    return self;
}

-(void)dealloc {
    [DebLog logN:@"DEALLOC PersistenceService"];
    [_permissions release];
    [super dealloc];
}

#pragma mark Public Methods

-(NSString *)getEntityName:(NSString *)entityName {
    if ([entityName containsString:@"."]) {
        NSArray *Array = [entityName componentsSeparatedByString:@"."];
        entityName = [Array lastObject];
    }
    if ([entityName isEqualToString: @"BackendlessUser"]) {
        entityName = @"Users";
    }
    return entityName;
}

// sync methods with fault return  (as exception)

-(NSArray<ObjectProperty *> *)describe:(NSString *)entityName {
    if (!entityName || [entityName isEqualToString:@""]) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, nil];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:@"describe" args:args];
}

-(NSDictionary *)save:(NSString *)entityName entity:(NSDictionary *)entity {
    if (!entity || !entityName) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, entity, nil];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_CREATE args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    return result;
}

-(NSDictionary *)update:(NSString *)entityName entity:(NSDictionary *)entity objectId:(NSString *)objectId {
    if (!entity || !entityName) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:entityName, entity, nil];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_UPDATE args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    return result;
}

-(id)save:(id)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [DebLog log:@"PersistenceService -> save: class = %@, entity = %@", [self objectClassName:entity], [self propertyDictionary:entity]];
    // 'save' = 'create' | 'update'
    id objectId = [self getObjectId:entity];
    BOOL isObjectId = objectId && [objectId isKindOfClass:NSString.class];
    NSString *method = isObjectId ? METHOD_UPDATE:METHOD_CREATE;
    [DebLog log:@"PersistenceService -> save: method = %@, objectId = %@", method, objectId];
    NSArray *args = @[[self objectClassName:entity], [self propertyObject:entity]];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:method args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    [self onCurrentUserUpdate:result];
    return result;
}

-(id)create:(id)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [DebLog log:@"PersistenceService -> create: class = %@, entity = %@", [self objectClassName:entity], entity];
    NSArray *args = @[[self objectClassName:entity],  [self propertyObject:entity]];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_CREATE args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    [self onCurrentUserUpdate:result];
    return result;
}

-(id)update:(id)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [DebLog log:@"PersistenceService -> update: class = %@, entity = %@", [self objectClassName:entity], entity];
    NSArray *args = @[[self objectClassName:entity],  [self propertyObject:entity]];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_UPDATE args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    [self onCurrentUserUpdate:result];
    return result;
}

-(id)load:(id)object relations:(NSArray *)relations {
    NSString *objectId = [self getObjectId:object];
    NSArray *args = @[[self objectClassName:object], [objectId isKindOfClass:[NSString class]] ? objectId:object, relations];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LOAD args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    return [self setRelations:relations object:object response:result];
}

-(id)load:(id)object relations:(NSArray *)relations relationsDepth:(int)relationsDepth {
    NSString *objectId = [self getObjectId:object];
    NSArray *args = @[[self objectClassName:object], [objectId isKindOfClass:[NSString class]] ? objectId:object, relations, @(relationsDepth)];
    id result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LOAD args:args];
    if ([result isKindOfClass:[Fault class]]) {
        return result;
    }
    return [self setRelations:relations object:object response:result];
}

-(NSArray *)find:(Class)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [DataQueryBuilder new]];
    if ([self isDeviceRegistrationClass:className]) {
        return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIND args:args responseAdapter:[DeviceRegistrationAdapter new]];
    }
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIND args:args];
}

-(NSArray *)find:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!queryBuilder) {
        return [backendless throwFault:FAULT_FIELD_IS_NULL];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [queryBuilder build]];
    if ([self isDeviceRegistrationClass:className]) {
        return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIND args:args responseAdapter:[DeviceRegistrationAdapter new]];
    }
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIND args:args];
}

-(id)first:(Class)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className]];
    if ([self isDeviceRegistrationClass:className]) {
        return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIRST args:args responseAdapter:[DeviceRegistrationAdapter new]];
    }
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIRST args:args];
}

-(id)first:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [queryBuilder getRelated], [queryBuilder getRelationsDepth]?[queryBuilder getRelationsDepth]:[NSNull null], [queryBuilder getProperties]];
    if ([self isDeviceRegistrationClass:className]) {
        return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIRST args:args responseAdapter:[DeviceRegistrationAdapter new]];
    }
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIRST args:args];
}

-(id)last:(Class)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className]];
    if ([self isDeviceRegistrationClass:className]) {
        return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LAST args:args responseAdapter:[DeviceRegistrationAdapter new]];
    }
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LAST args:args];
}

-(id)last:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [queryBuilder getRelated], [queryBuilder getRelationsDepth]?[queryBuilder getRelationsDepth]:[NSNull null], [queryBuilder getProperties]];
    if ([self isDeviceRegistrationClass:className]) {
        return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LAST args:args responseAdapter:[DeviceRegistrationAdapter new]];
    }
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LAST args:args];
}

-(id)findByObject:(id)entity {
    return [self findByObject:entity responseAdapter:[DefaultAdapter new]];
}

-(id)findByObject:(id)entity responseAdapter:(id<IResponseAdapter>)responseAdapter {
    if (!entity) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], [self propertyDictionary:entity]];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responseAdapter:responseAdapter];
}

-(id)findByObject:(id)entity queryBuilder:(DataQueryBuilder *)queryBuilder {
    return [self findByObject:entity queryBuilder:queryBuilder responseAdapter:[DefaultAdapter new]];
}

-(id)findByObject:(id)entity queryBuilder:(DataQueryBuilder *)queryBuilder responseAdapter:(id<IResponseAdapter>)responseAdapter {
    if (!entity) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], [self propertyDictionary:entity], [queryBuilder build]];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responseAdapter:responseAdapter];
}

-(id)findByObject:(id)entity relations:(NSArray *)relations {
    if (!entity) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], [self propertyDictionary:entity], relations];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args];
}

-(id)findByObject:(id)entity relations:(NSArray *)relations relationsDepth:(int)relationsDepth {
    if (!entity) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], [self propertyDictionary:entity], relations, @(relationsDepth)];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args];
}

-(id)findByObject:(NSString *)className keys:(NSDictionary *)props {
    return [self findByObject:className keys:props responseAdapter:[DefaultAdapter new]];
}

-(id)findByObject:(NSString *)className keys:(NSDictionary *)props responseAdapter:(id<IResponseAdapter>)responseAdapter {
    if (!className) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!props) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[className, props];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responseAdapter:responseAdapter];
}

-(id)findByObject:(NSString *)className keys:(NSDictionary *)props queryBuilder:(DataQueryBuilder *)queryBuilder {
    return [self findByObject:className keys:props queryBuilder:queryBuilder responseAdapter:[DefaultAdapter new]];
}

-(id)findByObject:(NSString *)className keys:(NSDictionary *)props queryBuilder:(DataQueryBuilder *)queryBuilder responseAdapter:(id<IResponseAdapter>)responseAdapter {
    if (!className) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!props) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[className, props, [queryBuilder build]];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responseAdapter:responseAdapter];
}

-(id)findByObject:(NSString *)className keys:(NSDictionary *)props relations:(NSArray *)relations {
    if (!className)
        return [backendless throwFault:FAULT_NO_ENTITY];
    if (!props)
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    NSArray *args = @[className, props, relations];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args];
}

-(id)findByObject:(NSString *)className keys:(NSDictionary *)props relations:(NSArray *)relations relationsDepth:(int)relationsDepth {
    if (!className)
        return [backendless throwFault:FAULT_NO_ENTITY];
    if (!props)
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    NSArray *args = @[className, props, relations, @(relationsDepth)];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args];
}

-(id)findById:(NSString *)entityName objectId:(NSString *)objectId {
    return [self findById:entityName objectId:objectId responseAdapter:[DefaultAdapter new]];
}

-(id)findById:(NSString *)entityName objectId:(NSString *)objectId responseAdapter:(id<IResponseAdapter>)responseAdapter {
    if (!entityName) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, objectId, nil];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responseAdapter:responseAdapter];
}

-(id)findById:(NSString *)entityName objectId:(NSString *)objectId queryBuilder:(DataQueryBuilder *)queryBuilder {
    return [self findById:entityName objectId:objectId queryBuilder:queryBuilder responseAdapter:[DefaultAdapter new]];
}

-(id)findById:(NSString *)entityName objectId:(NSString *)objectId queryBuilder:(DataQueryBuilder *)queryBuilder responseAdapter:(id)responseAdapter {
    if (!entityName) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, objectId, [queryBuilder build], nil];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responseAdapter:responseAdapter];
}

-(id)findByClassId:(Class)entity objectId:(NSString *)objectId {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:entity];
    NSArray *args = [NSArray arrayWithObjects:[self typeClassName:entity], objectId, nil];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args];
}

-(id)findByClassId:(Class)entity objectId:(NSString *)objectId queryBuilder:(DataQueryBuilder *)queryBuilder {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:entity];
    NSArray *args = [NSArray arrayWithObjects:[self typeClassName:entity], objectId, [queryBuilder build], nil];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args];
}

-(NSNumber *)remove:(id)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity], entity];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_REMOVE args:args];
}

-(NSNumber *)remove:(Class)entity objectId:(NSString *)objectId {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [backendless throwFault:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:[self typeClassName:entity], objectId, nil];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_REMOVE args:args];
}

-(NSArray *)callStoredProcedure:(NSString *)spName arguments:(NSDictionary *)arguments {
    if (!spName) {
        return [backendless throwFault:FAULT_NAME_IS_NULL];
    }
    if (!arguments) {
        arguments = [NSDictionary dictionary];
    }
    NSArray *args = @[spName, arguments];
    return [backendlessCache invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_CALL_STORED_PROCEDURE args:args];
}

-(NSNumber *)getObjectCount:(Class)entity {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self typeClassName:entity]];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_COUNT args:args];
}

-(NSNumber *)getObjectCount:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!queryBuilder) {
        return [backendless throwFault:FAULT_FIELD_IS_NULL];
    }
    NSString *className = [self getEntityName:NSStringFromClass(entity)];
    BackendlessDataQuery *dataQuery = [queryBuilder build];
    NSArray *args = @[className, dataQuery ? dataQuery:BACKENDLESS_DATA_QUERY];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_COUNT args:args];
}

-(NSNumber *)setRelation:(NSString *)parentObject columnName: (NSString *)columnName parentObjectId:(NSString *)parentObjectId childObjects:(NSArray *)childObjects {
    if (!parentObject) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, childObjects];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:CREATE_RELATION args:args];
}

-(NSNumber *)setRelation:(NSString *)parentObject columnName: (NSString *)columnName parentObjectId:(NSString *)parentObjectId whereClause:(NSString *)whereClause {
    if (!parentObject) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, whereClause];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:CREATE_RELATION args:args];
}

-(NSNumber *)addRelation:(NSString *)parentObject columnName: (NSString *)columnName parentObjectId:(NSString *)parentObjectId childObjects:(NSArray *)childObjects {
    if (!parentObject) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, childObjects];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:ADD_RELATION args:args];
}

-(NSNumber *)addRelation:(NSString *)parentObject columnName: (NSString *)columnName parentObjectId:(NSString *)parentObjectId whereClause:(NSString *)whereClause {
    if (!parentObject) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, whereClause];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:ADD_RELATION args:args];
}

-(NSNumber *)deleteRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId childObjects:(NSArray *)childObjects {
    if (!parentObject) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, childObjects];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:DELETE_RELATION args:args];
}

-(NSNumber *)deleteRelation:(NSString *)parentObject columnName: (NSString *)columnName parentObjectId:(NSString *)parentObjectId whereClause:(NSString *)whereClause {
    if (!parentObject) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, whereClause];
    return [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:DELETE_RELATION args:args];
}

-(id)loadRelations:(NSString *)parentType objectId:(NSString *)objectId queryBuilder:(LoadRelationsQueryBuilder *)queryBuilder {
    if (!parentType) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    if (!queryBuilder) {
        return [backendless throwFault:FAULT_FIELD_IS_NULL];
    }
    BackendlessDataQuery *dataQuery = [queryBuilder build];
    NSString *relationName = [dataQuery.queryOptions.related objectAtIndex:0];
    NSNumber *pageSize = dataQuery.pageSize;
    NSNumber *offset  = dataQuery.offset;
    NSArray *args = @[parentType, objectId, relationName, pageSize, offset];
    return  [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:LOAD_RELATION args:args];
}

-(NSNumber *)updateBulk:(id)entity whereClause:(NSString *)whereClause changes:(NSDictionary<NSString *, id> *)changes {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity], whereClause, changes];
    NSNumber *result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:UPDATE_BULK args:args];
    return result;
}

-(NSNumber *)removeBulk:(id)entity whereClause:(NSString *)whereClause {
    if (!entity) {
        return [backendless throwFault:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity], whereClause];
    NSNumber *result = [invoker invokeSync:SERVER_PERSISTENCE_SERVICE_PATH method:REMOVE_BULK args:args];
    return result;
}

// async methods with block-base callbacks

-(void)describe:(NSString *)entityName response:(void(^)(NSArray<ObjectProperty*> *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entityName || [entityName isEqualToString:@""]) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:@"describe" args:args responder:chainedResponder];
}

-(void)save:(NSString *)entityName entity:(NSDictionary *)entity response:(void(^)(NSDictionary *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity || !entityName) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, entity, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_CREATE args:args responder:chainedResponder];
}

-(void)update:(NSString *)entityName entity:(NSDictionary *)entity objectId:(NSString *)objectId response:(void(^)(NSDictionary *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity || !entityName) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:entityName, entity, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_UPDATE args:args responder:chainedResponder];
}

-(void)save:(id)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [DebLog log:@"PersistenceService -> save: class = %@, entity = %@", [self objectClassName:entity], [self propertyDictionary:entity]];
    // 'save' = 'create' | 'update'
    id objectId = [self getObjectId:entity];
    BOOL isObjectId = objectId && [objectId isKindOfClass:NSString.class];
    NSString *method = isObjectId ? METHOD_UPDATE:METHOD_CREATE;
    [DebLog log:@"PersistenceService -> save: method = %@, objectId = %@", method, objectId];
    NSArray *args = @[[self objectClassName:entity],  [self propertyObject:entity]];
    Responder *_responder = [Responder responder:chainedResponder selResponseHandler:@selector(createResponse:) selErrorHandler:nil];
    _responder.chained = chainedResponder;
    _responder.context = entity;
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:method args:args responder:_responder];
}

-(void)create:(id)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity],  [self propertyObject:entity]];
    Responder *_responder = [Responder responder:chainedResponder selResponseHandler:@selector(createResponse:) selErrorHandler:nil];
    _responder.chained = chainedResponder;
    _responder.context = entity;
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_CREATE args:args responder:_responder];
}

-(void)update:(id)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity],  [self propertyObject:entity]];
    Responder *_responder = [Responder responder:chainedResponder selResponseHandler:@selector(createResponse:) selErrorHandler:nil];
    _responder.chained = chainedResponder;
    _responder.context = entity;
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_UPDATE args:args responder:_responder];
}

-(void)find:(Class)entity response:(void (^)(NSArray *))responseBlock error:(void (^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [DataQueryBuilder new]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIND args:args responder:chainedResponder];
}

-(void)find:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(NSArray *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!queryBuilder) {
        return [chainedResponder errorHandler: FAULT_FIELD_IS_NULL];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [queryBuilder build]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIND args:args responder:chainedResponder];
}

-(void)first:(Class)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIRST args:args responder:chainedResponder];
}

-(void)first:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [queryBuilder getRelated], [queryBuilder getRelationsDepth]?[queryBuilder getRelationsDepth]:[NSNull null], [queryBuilder getProperties]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FIRST args:args responder:chainedResponder];
}

-(void)last:(Class)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LAST args:args responder:chainedResponder];
}

-(void)last:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    [self prepareClass:entity];
    NSString *className = [self typeClassName:entity];
    NSArray *args = @[[self getEntityName:className], [queryBuilder getRelated], [queryBuilder getRelationsDepth]?[queryBuilder getRelationsDepth]:[NSNull null], [queryBuilder getProperties]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_LAST args:args responder:chainedResponder];
}

-(void)findByObject:(id)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    [self findByObject:entity response:responseBlock error:errorBlock responseAdapter:[DefaultAdapter new]];
}

-(void)findByObject:(id)entity response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock responseAdapter:(id<IResponseAdapter>)responseAdapter {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], entity];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder responseAdapter:responseAdapter];
}

-(void)findByObject:(id)entity queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    [self findByObject:entity queryBuilder:queryBuilder response:responseBlock error:errorBlock responseAdapter:[DefaultAdapter new]];
}

-(void)findByObject:(id)entity queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock responseAdapter:(id<IResponseAdapter>)responseAdapter {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], entity, [queryBuilder build]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder responseAdapter:responseAdapter];
}

-(void)findByObject:(id)entity relations:(NSArray *)relations response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity],entity, relations];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder];
}

-(void)findByObject:(id)entity relations:(NSArray *)relations relationsDepth:(int)relationsDepth response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = @[[self objectClassName:entity], entity, relations, @(relationsDepth)];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder];
}

-(void)findByObject:(NSString *)className keys:(NSDictionary *)props response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    [self findByObject:className keys:props response:responseBlock error:errorBlock responseAdapter:[DefaultAdapter new]];
}

-(void)findByObject:(NSString *)className keys:(NSDictionary *)props response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock responseAdapter:(id<IResponseAdapter>)responseAdapter {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!className) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!props) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:className, props, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder responseAdapter:responseAdapter];
}

-(void)findByObject:(NSString *)className keys:(NSDictionary *)props queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    [self findByObject:className keys:props queryBuilder:queryBuilder response:responseBlock error:errorBlock responseAdapter:[DefaultAdapter new]];
}

-(void)findByObject:(NSString *)className keys:(NSDictionary *)props queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock responseAdapter:(id<IResponseAdapter>)responseAdapter {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!className) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!props) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:className, props, [queryBuilder build], nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder responseAdapter:responseAdapter];
}

-(void)findByObject:(NSString *)className keys:(NSDictionary *)props relations:(NSArray *)relations response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!className) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!props) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:className, props, relations, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder];
}

-(void)findByObject:(NSString *)className keys:(NSDictionary *)props relations:(NSArray *)relations relationsDepth:(int)relationsDepth response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!className) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!props) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    NSArray *args = [NSArray arrayWithObjects:className, props, relations, @(relationsDepth), nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder];
}

-(void)findById:(NSString *)entityName objectId:(NSString *)objectId response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    [self findById:entityName objectId:objectId response:responseBlock error:errorBlock responseAdapter:[DefaultAdapter new]];
}

-(void)findById:(NSString *)entityName objectId:(NSString *)objectId response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock responseAdapter:(id<IResponseAdapter>)responseAdapter {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entityName) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, objectId, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder responseAdapter:responseAdapter];
}

-(void)findById:(NSString *)entityName objectId:(NSString *)objectId queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    [self findById:entityName objectId:objectId queryBuilder:queryBuilder response:responseBlock error:errorBlock responseAdapter:[DefaultAdapter new]];
}

-(void)findById:(NSString *)entityName objectId:(NSString *)objectId queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock responseAdapter:(id<IResponseAdapter>)responseAdapter {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entityName) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:NSClassFromString(entityName)];
    NSArray *args = [NSArray arrayWithObjects:entityName, objectId, [queryBuilder build], nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder responseAdapter:responseAdapter];
}

-(void)findByClassId:(Class)entity objectId:(NSString *)objectId response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:entity];
    NSArray *args = [NSArray arrayWithObjects:[self typeClassName:entity], objectId, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder];
}

-(void)findByClassId:(Class)entity objectId:(NSString *)objectId queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(id))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:entity];
    NSArray *args = [NSArray arrayWithObjects:[self typeClassName:entity], objectId, [queryBuilder build], nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_FINDBYID args:args responder:chainedResponder];
}

-(void)remove:(id)entity response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity], entity];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_REMOVE args:args responder:chainedResponder];
}

-(void)remove:(Class)entity objectId:(NSString *)objectId response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!objectId) {
        return [chainedResponder errorHandler:FAULT_OBJECT_ID_IS_NOT_EXIST];
    }
    [self prepareClass:entity];
    NSArray *args = [NSArray arrayWithObjects:[self typeClassName:entity], objectId, nil];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_REMOVE args:args responder:chainedResponder];
}

-(void)callStoredProcedure:(NSString *)spName arguments:(NSDictionary *)arguments response:(void(^)(NSArray *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!spName) {
        return [chainedResponder errorHandler:FAULT_NAME_IS_NULL];
    }
    if (!arguments) {
        arguments = [NSDictionary dictionary];
    }
    NSArray *args = @[spName, arguments];
    [backendlessCache invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_CALL_STORED_PROCEDURE args:args responder:chainedResponder];
}

-(void)getObjectCount:(Class)entity response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self typeClassName:entity]];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_COUNT args:args responder:chainedResponder];
}

-(void)getObjectCount:(Class)entity queryBuilder:(DataQueryBuilder *)queryBuilder response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!queryBuilder) {
        return [chainedResponder errorHandler: FAULT_FIELD_IS_NULL];
    }
    NSString *className = [self getEntityName:NSStringFromClass(entity)];
    BackendlessDataQuery *dataQuery = [queryBuilder build];
    NSArray *args = @[className, dataQuery ? dataQuery:BACKENDLESS_DATA_QUERY];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:METHOD_COUNT args:args responder:chainedResponder];
}

-(void)setRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId childObjects:(NSArray *)childObjects response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentObject) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, childObjects];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:CREATE_RELATION args:args responder:chainedResponder];
}

-(void)setRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId whereClause:(NSString *)whereClause response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentObject) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, whereClause];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:CREATE_RELATION args:args responder:chainedResponder];
}

-(void)addRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId childObjects:(NSArray *)childObjects response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentObject) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, childObjects];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:ADD_RELATION args:args responder:chainedResponder];
}

-(void)addRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId whereClause:(NSString *)whereClause response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentObject) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, whereClause];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:ADD_RELATION args:args responder:chainedResponder];
}


-(void)deleteRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId childObjects:(NSArray *)childObjects response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentObject) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, childObjects];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:DELETE_RELATION args:args responder:chainedResponder];
}

-(void)deleteRelation:(NSString *)parentObject columnName:(NSString *)columnName parentObjectId:(NSString *)parentObjectId whereClause:(NSString *)whereClause response:(void(^)(NSNumber *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentObject) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[parentObject, columnName, parentObjectId, whereClause];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:DELETE_RELATION args:args responder:chainedResponder];
}

-(void)loadRelations:(NSString *)parentType objectId:(NSString *)objectId queryBuilder:(LoadRelationsQueryBuilder *)queryBuilder response:(void(^)(NSArray *))responseBlock error:(void(^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!parentType) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    if (!queryBuilder) {
        return [chainedResponder errorHandler:FAULT_FIELD_IS_NULL];
    }
    BackendlessDataQuery *dataQuery = [queryBuilder build];
    NSString *relationName = [dataQuery.queryOptions.related objectAtIndex:0];
    NSNumber *pageSize = dataQuery.pageSize;
    NSNumber *offset  = dataQuery.offset;
    NSArray *args = @[parentType, objectId, relationName, pageSize, offset];
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:LOAD_RELATION args:args responder:chainedResponder];
}

-(void)updateBulk:(id)entity whereClause:(NSString *)whereClause changes:(NSDictionary<NSString *,id> *)changes response:(void (^)(id))responseBlock error:(void (^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity], whereClause, changes];
    Responder *_responder = [Responder responder:chainedResponder selResponseHandler:@selector(createResponse:) selErrorHandler:nil];
    _responder.chained = chainedResponder;
    _responder.context = entity;
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:UPDATE_BULK args:args responder:_responder];
}

-(void)removeBulk:(id)entity whereClause:(NSString *)whereClause response:(void (^)(id))responseBlock error:(void (^)(Fault *))errorBlock {
    Responder *chainedResponder = [ResponderBlocksContext responderBlocksContext:responseBlock error:errorBlock];
    if (!entity) {
        return [chainedResponder errorHandler:FAULT_NO_ENTITY];
    }
    NSArray *args = @[[self objectClassName:entity], whereClause];
    Responder *_responder = [Responder responder:chainedResponder selResponseHandler:@selector(createResponse:) selErrorHandler:nil];
    _responder.chained = chainedResponder;
    _responder.context = entity;
    [invoker invokeAsync:SERVER_PERSISTENCE_SERVICE_PATH method:REMOVE_BULK args:args responder:_responder];
}

// IDataStore class factory
-(id <IDataStore>)of:(Class)entityClass {
    return [DataStoreFactory createDataStore:entityClass];
}

// MapDrivenDataStore factory
-(MapDrivenDataStore *)ofTable:(NSString *)tableName {
    return [MapDrivenDataStore createDataStore:tableName];
}

// utilites
-(id)getObjectId:(id)object {
    id objectId = nil;
    return [object getPropertyIfResolved:PERSIST_OBJECT_ID value:&objectId] ? objectId : [NSNumber numberWithBool:NO];
}

-(NSDictionary *)getObjectMetadata:(id)object {
    const NSString *metadataKeys = @",___class,__meta,created,objectId,updated,";
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    NSDictionary *props = [self propertyDictionary:object];
    NSArray *keys = [props allKeys];
    for (NSString *key in keys) {
        NSRange rang = [metadataKeys rangeOfString:[NSString stringWithFormat:@",%@,",key]];
        if (rang.length) {
            id obj = [props valueForKey:key];
            if (obj) {
                [metadata setObject:obj forKey:key];
            }
        }
    }
    return metadata;
}

-(void)mapTableToClass:(NSString *)tableName type:(Class)type {
    [[Types sharedInstance] addClientClassMapping:tableName mapped:type];
}

-(void)mapColumnToProperty:(Class)classToMap columnName:(NSString *)columnName propertyName:(NSString *)propertyName {
    [[Types sharedInstance] addClientPropertyMappingForClass:classToMap columnName:columnName propertyName:propertyName];
}

#pragma mark Private Methods

-(NSDictionary *)filteringProperty:(id)object {
    return [self propertyDictionary:object];
}

-(BOOL)prepareClass:(Class)className {
    id object = [__types classInstance:className];
    BOOL result = [object resolveProperty:PERSIST_OBJECT_ID];
    [object resolveProperty:@"__meta"];
    return result;
}

-(BOOL)prepareObject:(id)object {
    [object resolveProperty:PERSIST_OBJECT_ID value:nil];
    [object resolveProperty:@"__meta" value:nil];
    return YES;
}

-(NSString *)typeClassName:(Class)entity {
    NSString *name = [__types typeMappedClassName:entity];
    if ([name isEqualToString:NSStringFromClass([BackendlessUser class])]) {
        name = @"Users";
    }
    return name;
}

-(NSString *)objectClassName:(id)object {
    NSString *name = [__types objectMappedClassName:object];
    if ([name isEqualToString:NSStringFromClass([BackendlessUser class])]) {
        name = @"Users";
    }
    return name;
}

-(NSDictionary *)propertyDictionary:(id)object {
    if ([[object class] isSubclassOfClass:[BackendlessUser class]]) {
        NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:[(BackendlessUser *)object getProperties]];
        [data removeObjectsForKeys:@[BACKENDLESS_USER_TOKEN, BACKENDLESS_USER_REGISTERED]];
        return data;
    }
    return [Types propertyDictionary:object];
}

-(id)propertyObject:(id)object {
    if ([[object class] isSubclassOfClass:[BackendlessUser class]]) {
        
        NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:[(BackendlessUser *) object getProperties]];
        [data removeObjectsForKeys:@[BACKENDLESS_USER_TOKEN, BACKENDLESS_USER_REGISTERED]];
        return data;
    }
    return object;
}

-(id)setRelations:(NSArray *)relations object:(id)object response:(id)response {
    NSArray *keys = [response allKeys];
    for (NSString *propertyName in keys) {
        id value = [response valueForKey:propertyName];
        if ([value isKindOfClass:[NSNull class]]) {
            continue;
        }
        if ([[object class] isSubclassOfClass:[BackendlessUser class]]) {
            [(BackendlessUser *)object setProperty:propertyName object:value];
            continue;
        }
        [object setValue:value forKey:propertyName];
    }
    return object;
}

-(BOOL)isDeviceRegistrationClass:(NSString *)className {
    if ([className isEqualToString:@"DeviceRegistration"]) {
        return YES;
    }
    return NO;
}

#pragma mark Callback Methods

-(id)loadRelations:(ResponseContext *)response {
    NSArray *relations = [response.context valueForKey:@"relations"];
    id object = [response.context valueForKey:@"object"];
    return [self setRelations:relations object:object response:response.response];
}

-(id)createResponse:(ResponseContext *)response {
    id object = response.context;
    [self onCurrentUserUpdate:response.response];
    response.context = nil;
    return response.response;
}

-(id)onCurrentUserUpdate:(id)result {
    if (![result isKindOfClass:[BackendlessUser class]]) {
        return result;
    }
    BackendlessUser *user = (BackendlessUser *)result;
    if (backendless.userService.isStayLoggedIn && backendless.userService.currentUser && [user.objectId isEqualToString:backendless.userService.currentUser.objectId]) {
        backendless.userService.currentUser = user;
        [backendless.userService setPersistentUser];
    }
    return user;
}

@end
