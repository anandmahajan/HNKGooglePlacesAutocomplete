//
//  HNKGooglePlacesAutocompleteQuery.m
//  HNKGooglePlacesAutocomplete
//
// Copyright (c) 2015 Harlan Kellaway
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "HNKGooglePlacesAutocompleteQuery.h"
#import "HNKGooglePlacesServer.h"
#import "HNKQueryResponse.h"

#pragma mark Error Domain

NSString *const HNKGooglePlacesAutocompleteQueryErrorDomain =
    @"com.hnkgoogleplacesautocomplete.query.fetch.error";

#pragma mark Request Constants

static NSString *const kHNKGooglePlacesServerRequestPathAutocomplete =
    @"autocomplete/json";
static NSInteger const kHNKGooglePlacesAutocompleteDefaultSearchRadius = 500;

#pragma mark Status Constants

static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionUnknown =
        @"Status unknown";
static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionInvalidRequest =
        @"Invalid request; the input parameter may be missing";
static NSString *const HNKGooglePlacesAutocompleteQueryStatusDescriptionOK =
    @"No errors occurred and at least one result was returned";
static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionOverQueryLimit =
        @"Query quota has been exceeded for provided API key";
static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionRequestDenied =
        @"Request denied; the key parameter may be invalid";
static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionZeroResults =
        @"No errors occurred but no results were returned";
static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionServerRequestFailed =
        @"Non-API error occurred while making a request to the server";
static NSString *const
    HNKGooglePlacesAutocompleteQueryStatusDescriptionSearchQueryNil =
        @"Search query cannot be nil";

@interface HNKGooglePlacesAutocompleteQuery ()

@property(nonatomic, copy, readwrite) NSString *apiKey;

@end

@implementation HNKGooglePlacesAutocompleteQuery

#pragma mark - Initialization

static HNKGooglePlacesAutocompleteQuery *sharedQuery = nil;

+ (instancetype)setupSharedQueryWithAPIKey:(NSString *)apiKey {
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    sharedQuery = [[self alloc] initWithAPIKey:apiKey];
  });

  return sharedQuery;
}

+ (instancetype)sharedQuery {
  NSAssert(
      sharedQuery != nil,
      @"sharedQuery should not be called before setupSharedQueryWithAPIKey");

  return sharedQuery;
}

- (instancetype)initWithAPIKey:(NSString *)apiKey {
  self = [super init];

  if (self) {

    self.apiKey = apiKey;
  }

  return self;
}

- (instancetype)init {
  NSAssert(FALSE, @"init should not be called");

  return [self initWithAPIKey:@""];
}

#pragma mark - Getters

- (NSString *)apiKey {
  return _apiKey;
}

#pragma mark - Requests

- (void)fetchPlacesForSearchQuery:(NSString *)searchQuery
                       completion:(HNKGooglePlacesAutocompleteQueryCallback)
                                      completion {
  if ([self isValidSearchQuery:searchQuery]) {

    [self serverRequestWithSearchQuery:searchQuery completion:completion];

  } else {

    [self completeWithErrorForInvalidSearchQuery:searchQuery
                                      completion:completion];
  }
}

#pragma mark - Helpers

- (BOOL)isValidSearchQuery:(NSString *)searchQuery {
  return ((searchQuery != nil) && ![searchQuery isEqualToString:@""]);
}

- (void)serverRequestWithSearchQuery:(NSString *)searchQuery
                          completion:(HNKGooglePlacesAutocompleteQueryCallback)
                                         completion {
  [HNKGooglePlacesServer
             GET:kHNKGooglePlacesServerRequestPathAutocomplete
      parameters:@{
        @"input" : searchQuery,
        @"key" : self.apiKey,
        @"radius" : @(kHNKGooglePlacesAutocompleteDefaultSearchRadius)
      }
      completion:^(NSDictionary *JSON, NSError *error) {

        if (completion) {

          if (error) {

            [self completeWithServerError:error completion:completion];

          } else {

            [self completeWithServerResponse:JSON completion:completion];
          }
        }

      }];
}

- (void)completeWithServerResponse:(NSDictionary *)JSON
                        completion:(HNKGooglePlacesAutocompleteQueryCallback)
                                       completion {
  HNKQueryResponse *queryResponse =
      [HNKQueryResponse modelFromJSONDictionary:JSON];
  NSError *statusError = [self customErrorForStatus:queryResponse.status];

  if (statusError) {

    completion(nil, statusError);

  } else {

    completion(queryResponse.predictions, nil);
  }
}

- (void)completeWithServerError:(NSError *)error
                     completion:
                         (HNKGooglePlacesAutocompleteQueryCallback)completion {
  NSError *errorToReturn = [self
      customErrorWithCode:
          HNKGooglePlacesAutcompleteQueryErrorCodeServerRequestFailed
              description:
                  HNKGooglePlacesAutocompleteQueryStatusDescriptionServerRequestFailed
              andUserInfo:@{
                @"NSUnderlyingError" : error
              }];

  completion(nil, errorToReturn);
}

- (void)completeWithErrorForInvalidSearchQuery:
            (NSString *)searchQuery completion:
                (HNKGooglePlacesAutocompleteQueryCallback)completion {
  if (searchQuery == nil) {

    [self completeForSearchQueryNil:completion];
    return;
  }

  if ([searchQuery isEqualToString:@""]) {

    [self completeForSearchQueryEmpty:completion];
    return;
  }
}

- (void)completeForSearchQueryNil:
        (HNKGooglePlacesAutocompleteQueryCallback)completion {
  NSError *error = [self
      customErrorWithCode:
          HNKGooglePlacesAutocompleteQueryErrorCodeSearchQueryNil
           andDescription:
               HNKGooglePlacesAutocompleteQueryStatusDescriptionSearchQueryNil];

  completion(nil, error);
}

- (void)completeForSearchQueryEmpty:
        (HNKGooglePlacesAutocompleteQueryCallback)completion {
  NSError *error =
      [self customErrorForStatus:HNKQueryResponseStatusInvalidRequest];

  completion(nil, error);
}

- (NSError *)customErrorForStatus:(HNKQueryResponseStatus)status {
  if (status == HNKQueryResponseStatusInvalidRequest ||
      status == HNKQueryResponseStatusOverQueryLimit ||
      status == HNKQueryResponseStatusRequestDenied ||
      status == HNKQueryResponseStatusUnknown) {

    HNKGooglePlacesAutocompleteQueryErrorCode errorCode =
        [self errorCodeForStatus:status];
    NSString *description =
        HNKGooglePlacesAutocompleteQueryDescriptionForErrorCode(errorCode);

    return [self customErrorWithCode:status andDescription:description];
  }

  return nil;
}

- (NSError *)customErrorWithCode:(NSInteger)errorCode
                  andDescription:(NSString *)errorDescription {
  return [self customErrorWithCode:errorCode
                       description:errorDescription
                       andUserInfo:nil];
}
- (NSError *)customErrorWithCode:(NSInteger)errorCode
                     description:(NSString *)errorDescription
                     andUserInfo:(NSDictionary *)userInfo {
  NSDictionary *userInfoToReturn = @{
    @"NSLocalizedDescription" : errorDescription,
    @"NSLocalizedFailureReasonError" : errorDescription
  };

  if (userInfo != nil) {
    NSMutableDictionary *mutableDictionary = [userInfoToReturn mutableCopy];
    [mutableDictionary addEntriesFromDictionary:userInfo];
    userInfoToReturn = [mutableDictionary copy];
  }

  return [NSError errorWithDomain:HNKGooglePlacesAutocompleteQueryErrorDomain
                             code:errorCode
                         userInfo:userInfoToReturn];
}

- (HNKGooglePlacesAutocompleteQueryErrorCode)errorCodeForStatus:
        (HNKQueryResponseStatus)status {
  switch (status) {
  case HNKQueryResponseStatusUnknown: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeUnknown;
    break;
  }
  case HNKQueryResponseStatusInvalidRequest: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeInvalidRequest;
    break;
  }
  case HNKQueryResponseStatusOK: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeUnknown;
    break;
  }
  case HNKQueryResponseStatusOverQueryLimit: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeOverQueryLimit;
    break;
  }
  case HNKQueryResponseStatusRequestDenied: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeRequestDenied;
    break;
  }
  case HNKQueryResponseStatusZeroResults: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeUnknown;
    break;
  }
  default: {
    return HNKGooglePlacesAutocompleteQueryErrorCodeUnknown;
    break;
  }
  }
}

NSString *HNKGooglePlacesAutocompleteQueryDescriptionForErrorCode(
    HNKGooglePlacesAutocompleteQueryErrorCode errorCode) {
  switch (errorCode) {
  case HNKGooglePlacesAutocompleteQueryErrorCodeUnknown: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionUnknown;
    break;
  }
  case HNKGooglePlacesAutocompleteQueryErrorCodeInvalidRequest: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionInvalidRequest;
    break;
  }
  case HNKGooglePlacesAutocompleteQueryErrorCodeOverQueryLimit: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionOverQueryLimit;
    break;
  }
  case HNKGooglePlacesAutocompleteQueryErrorCodeRequestDenied: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionRequestDenied;
    break;
  }
  case HNKGooglePlacesAutcompleteQueryErrorCodeServerRequestFailed: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionServerRequestFailed;
    break;
  }
  case HNKGooglePlacesAutocompleteQueryErrorCodeSearchQueryNil: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionSearchQueryNil;
    break;
  }
  default: {
    return HNKGooglePlacesAutocompleteQueryStatusDescriptionUnknown;
    break;
  }
  }
}

@end
