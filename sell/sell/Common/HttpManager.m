//
//  HttpManager.m
//  eAinng
//
//  Created by tmachc on 15/2/25.
//  Copyright (c) 2015年 CCWOnline. All rights reserved.
//

#import "HttpManager.h"

@implementation NSString (HttpManager)
- (NSString *)md5
{
    if(self == nil || [self length] == 0){
        return nil;
    }
    const char *value = [self UTF8String];
    
    unsigned char outputBuffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(value, (CC_LONG)strlen(value), outputBuffer);
    
    NSMutableString *outputString = [[NSMutableString alloc] initWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(NSInteger count = 0; count < CC_MD5_DIGEST_LENGTH; count++){
        [outputString appendFormat:@"%02x",outputBuffer[count]];
    }
    
    return outputString;
}
- (NSString *)encode
{
    NSString *outputStr = (NSString *)
    CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                              (CFStringRef)self,
                                                              NULL,
                                                              NULL,
                                                              kCFStringEncodingUTF8));
    return outputStr;
}
- (NSString *)decode
{
    NSMutableString *outputStr = [NSMutableString stringWithString:self];
    [outputStr replaceOccurrencesOfString:@"+" withString:@" " options:NSLiteralSearch range:NSMakeRange(0, [outputStr length])];
    return [outputStr stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}
- (NSString *)utf8
{
    NSMutableString *outputStr = [NSMutableString stringWithString:self];
    return [[outputStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
}
- (id)object
{
    id object = nil;
    @try {
        NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];;
        object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:nil];
    }
    @catch (NSException *exception) {
        NSLog(@"%s [Line %d] JSON字符串转换成对象出错了-->\n%@",__PRETTY_FUNCTION__, __LINE__,exception);
    }
    @finally {
    }
    return object;
}
@end
@implementation NSObject (HttpManager)
- (NSString *)json
{
    NSString *jsonStr = @"";
    @try {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self options:0 error:nil];
        jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    @catch (NSException *exception) {
        NSLog(@"%s [Line %d] 对象转换成JSON字符串出错了-->\n%@",__PRETTY_FUNCTION__, __LINE__,exception);
    }
    @finally {
    }
    return jsonStr;
}
@end

@interface HttpManager ()
{
    AFHTTPRequestOperationManager *operationManager;
}
@end

@implementation HttpManager

- (id)init{
    self = [super init];
    if (self) {
        operationManager = [AFHTTPRequestOperationManager manager];
        operationManager.responseSerializer.acceptableContentTypes = nil;
        
        NSURLCache *urlCache = [NSURLCache sharedURLCache];
        [urlCache setMemoryCapacity:5*1024*1024];  /* 设置缓存的大小为5M*/
        [NSURLCache setSharedURLCache:urlCache];
    }
    return self;
}


+ (HttpManager *)defaultManager
{
    static dispatch_once_t pred = 0;
    __strong static id defaultHttpManager = nil;
    dispatch_once( &pred, ^{
        defaultHttpManager = [[self alloc] init];
    });
    return defaultHttpManager;
}

- (void)getRequestToUrl:(NSString *)url params:(NSDictionary *)params complete:(void (^)(BOOL successed, NSDictionary *result))complete
{
    [self requestToUrl:url method:@"GET" useCache:NO params:params complete:^(BOOL successed, NSDictionary *result) {
        if (successed) {
            if ([result[@"result"] boolValue]) {
                complete(true,result);
            }
            else {
                complete(false,result);
            }
        }
        else {
            // 失败，弹提示
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"提示" message:@"请求数据失败" delegate:self cancelButtonTitle:@"知道了" otherButtonTitles:nil, nil];
            [alert show];
            complete(false,@{@"message":@"请求数据失败"});
        }
    }];
}

- (void)getCacheToUrl:(NSString *)url params:(NSDictionary *)params complete:(void (^)(BOOL successed, NSDictionary *result))complete
{
    [self requestToUrl:url method:@"GET" useCache:YES params:params complete:complete];
}

- (void)postRequestToUrl:(NSString *)url params:(NSDictionary *)params complete:(void (^)(BOOL successed, NSDictionary *result))complete
{
    [self requestToUrl:url method:@"POST" useCache:NO params:params complete:^(BOOL successed, NSDictionary *result) {
        if (successed) {
            if ([result[@"result"] boolValue]) {
                complete(true,result);
            }
            else {
                complete(false,result);
            }
        }
        else {
            complete(false,@{@"message":@"请求数据失败"});
        }
    }];
}

- (void)requestToUrl:(NSString *)url method:(NSString *)method useCache:(BOOL)useCache
              params:(NSDictionary *)params complete:(void (^)(BOOL successed, NSDictionary *result))complete
{
    NSMutableDictionary *requestBody = [[HttpManager getRequestBodyWithParams:params] mutableCopy];
    params = [NSDictionary dictionaryWithDictionary:requestBody];
    
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    NSMutableURLRequest *request = [serializer requestWithMethod:method URLString:url parameters:params error:nil];
    
    [request setTimeoutInterval:10];
    if (useCache) {
        [request setCachePolicy:NSURLRequestReturnCacheDataElseLoad];
    }
    
    void (^requestSuccessBlock)(AFHTTPRequestOperation *operation, id responseObject) = ^(AFHTTPRequestOperation *operation, id responseObject) {
        [self showMessageWithOperation:operation method:method params:params];
        
        complete ? complete(true,responseObject) : nil;
    };
    void (^requestFailureBlock)(AFHTTPRequestOperation *operation, NSError *error) = ^(AFHTTPRequestOperation *operation, NSError *error) {
        [self showMessageWithOperation:operation method:method params:params];
        
        complete ? complete(false,nil) : nil;
    };
    
    AFHTTPRequestOperation *operation = nil;
    if (useCache) {
        operation = [self cacheOperationWithRequest:request success:requestSuccessBlock failure:requestFailureBlock];
    }else{
        operation = [operationManager HTTPRequestOperationWithRequest:request success:requestSuccessBlock failure:requestFailureBlock];
    }
    [operationManager.operationQueue addOperation:operation];
}

- (AFHTTPRequestOperation *)cacheOperationWithRequest:(NSURLRequest *)urlRequest
                                              success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                                              failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    AFHTTPRequestOperation *operation = [operationManager HTTPRequestOperationWithRequest:urlRequest success:^(AFHTTPRequestOperation *operation, id responseObject){
        NSCachedURLResponse *cachedURLResponse = [[NSURLCache sharedURLCache] cachedResponseForRequest:urlRequest];
        
        //store in cache
        cachedURLResponse = [[NSCachedURLResponse alloc] initWithResponse:operation.response data:operation.responseData userInfo:nil storagePolicy:NSURLCacheStorageAllowed];
        [[NSURLCache sharedURLCache] storeCachedResponse:cachedURLResponse forRequest:urlRequest];
        
        success(operation,responseObject);
        
    }failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (error.code == kCFURLErrorNotConnectedToInternet) {
            NSCachedURLResponse *cachedResponse = [[NSURLCache sharedURLCache] cachedResponseForRequest:urlRequest];
            if (cachedResponse != nil && [[cachedResponse data] length] > 0) {
                success(operation, cachedResponse.data);
            } else {
                failure(operation, error);
            }
        } else {
            failure(operation, error);
        }
    }];
    
    return operation;
}

- (AFHTTPRequestOperation *)uploadToUrl:(NSString *)url
                                 params:(NSDictionary *)params
                                  files:(NSArray *)files
                               complete:(void (^)(BOOL successed, NSDictionary *result))complete
{
    return [self uploadToUrl:url params:params files:files process:nil complete:complete];
}

- (AFHTTPRequestOperation *)uploadToUrl:(NSString *)url
                                 params:(NSDictionary *)params
                                  files:(NSArray *)files
                                process:(void (^)(NSInteger writedBytes, NSInteger totalBytes))process
                               complete:(void (^)(BOOL successed, NSDictionary *result))complete
{
    params = [[HttpManager getRequestBodyWithParams:params] copy];
    FLOG(@"post request url:  %@  \npost params:  %@",url,params);
    
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    
    NSMutableURLRequest *request = [serializer multipartFormRequestWithMethod:@"POST" URLString:url parameters:params constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        for (NSDictionary *fileItem in files) {
            id value = [fileItem objectForKey:@"file"];    //支持四种数据类型：NSData、UIImage、NSURL、NSString
            NSString *name = @"file";                                   //字段名称
            NSString *fileName = [fileItem objectForKey:@"name"];       //文件名称
            NSString *mimeType = [fileItem objectForKey:@"type"];       //文件类型
            mimeType = mimeType ? mimeType : @"image/jpeg";
            
            if ([value isKindOfClass:[NSData class]]) {
                [formData appendPartWithFileData:value name:name fileName:fileName mimeType:mimeType];
            }else if ([value isKindOfClass:[UIImage class]]) {
                if (UIImagePNGRepresentation(value)) {  //返回为png图像。
                    [formData appendPartWithFileData:UIImagePNGRepresentation(value) name:name fileName:fileName mimeType:mimeType];
                }else {   //返回为JPEG图像。
                    [formData appendPartWithFileData:UIImageJPEGRepresentation(value, 0.5) name:name fileName:fileName mimeType:mimeType];
                }
            }else if ([value isKindOfClass:[NSURL class]]) {
                [formData appendPartWithFileURL:value name:name fileName:fileName mimeType:mimeType error:nil];
            }else if ([value isKindOfClass:[NSString class]]) {
                [formData appendPartWithFileURL:[NSURL URLWithString:value]  name:name fileName:fileName mimeType:mimeType error:nil];
            }
        }
    } error:nil];
    
    AFHTTPRequestOperation *operation = nil;
    operation = [operationManager HTTPRequestOperationWithRequest:request
                                                          success:^(AFHTTPRequestOperation *operation, id responseObject) {
                                                              FLOG(@"post responseObject:  %@",responseObject);
                                                              if (complete) {
                                                                  complete(true,responseObject);
                                                              }
                                                          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                              FLOG(@"post error :  %@",error);
                                                              if (complete) {
                                                                  complete(false,nil);
                                                              }
                                                          }];
    
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        FLOG(@"upload process: %.2lld%% (%ld/%ld)",100*totalBytesWritten/totalBytesExpectedToWrite,(long)totalBytesWritten,(long)totalBytesExpectedToWrite);
        if (process) {
            process(totalBytesWritten,totalBytesExpectedToWrite);
        }
    }];
    [operation start];
    
    return operation;
}

- (AFHTTPRequestOperation *)downloadFromUrl:(NSString *)url
                                   filePath:(NSString *)filePath
                                   complete:(void (^)(BOOL successed, NSDictionary *response))complete
{
    return [self downloadFromUrl:url params:nil filePath:filePath process:nil complete:complete];
}

- (AFHTTPRequestOperation *)downloadFromUrl:(NSString *)url
                                     params:(NSDictionary *)params
                                   filePath:(NSString *)filePath
                                    process:(void (^)(NSInteger readBytes, NSInteger totalBytes))process
                                   complete:(void (^)(BOOL successed, NSDictionary *response))complete
{
    params = [[HttpManager getRequestBodyWithParams:params] copy];
    
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    NSMutableURLRequest *request = [serializer requestWithMethod:@"GET" URLString:url parameters:params error:nil];
    FLOG(@"get request url: %@",[request.URL.absoluteString decode]);
    
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    operation.responseSerializer.acceptableContentTypes = nil;
    
    NSString *tmpPath = [filePath stringByAppendingString:@".tmp"];
    operation.outputStream=[[NSOutputStream alloc] initToFileAtPath:tmpPath append:NO];
    
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSArray *mimeTypeArray = @[@"text/html", @"application/json"];
        NSError *moveError = nil;
        if ([mimeTypeArray containsObject:operation.response.MIMEType]) {
            //返回的是json格式数据
            responseObject = [NSData dataWithContentsOfFile:tmpPath];
            responseObject = [NSJSONSerialization JSONObjectWithData:responseObject options:2 error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
            FLOG(@"get responseObject:  %@",responseObject);
        }else{
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:filePath error:&moveError];
        }
        
        if (complete && !moveError) {
            complete(true,responseObject);
        }else{
            complete?complete(false,responseObject):nil;
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        FLOG(@"get error :  %@",error);
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        if (complete) {
            complete(false,nil);
        }
    }];
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
        FLOG(@"download process: %.2lld%% (%ld/%ld)",100*totalBytesRead/totalBytesExpectedToRead,(long)totalBytesRead,(long)totalBytesExpectedToRead);
        if (process) {
            process(totalBytesRead,totalBytesExpectedToRead);
        }
    }];
    
    [operation start];
    
    return operation;
}

+ (NSMutableDictionary *)getRequestBodyWithParams:(NSDictionary *)params
{
    NSMutableDictionary *requestBody = params?[params mutableCopy]:[[NSMutableDictionary alloc] init];
    
    for (NSString *key in [params allKeys]){
        id value = [params objectForKey:key];
        if ([value isKindOfClass:[NSDate class]]) {
            [requestBody setValue:@([value timeIntervalSince1970]*1000) forKey:key];
        }
        if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
            [requestBody setValue:[value json] forKey:key];
        }
    }
    
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:@"id"];
    if (token){
        [requestBody setObject:token forKey:@"userId"];
    }
    
//    [requestBody setObject:@"userId" forKey:@"genus"];
    
    return requestBody;
}

+ (NetworkStatus)networkStatus
{
    Reachability *reachability = [Reachability reachabilityWithHostName:@"www.baidu.com"];
    // NotReachable     - 没有网络连接               - 0
    // ReachableViaWiFi - 移动网络(2G、3G)WIFI网络   - 1
    // ReachableViaWWAN - 移动网络(2G、3G)          - 2
    return [reachability currentReachabilityStatus];
}


- (void)showMessageWithOperation:(AFHTTPRequestOperation *)operation method:(NSString *)method params:(NSDictionary *)params
{
    NSString *urlAbsoluteString = [operation.request.URL.absoluteString decode];
    if ([[method uppercaseString] isEqualToString:@"GET"]) {
        FLOG(@"get request url:  %@  \n",urlAbsoluteString);
    }else{
        FLOG(@"%@ request url:  %@  \npost params:  %@\n",[method lowercaseString],urlAbsoluteString,params);
    }
    if (operation.error) {
        FLOG(@"%@ error :  %@",[method lowercaseString],operation.error);
    }else{
        FLOG(@"%@ responseObject:  %@",[method lowercaseString],operation.responseObject);
    }
    
//    //只显示一部分url
//    NSArray *ignordUrls = @[url_originalDataDownload,url_originalDataUpload,url_originalDataUploadFinished,url_getEarliestOriginalData,url_newVersion,
//                            url_saveSyncFailInfo];
//    for (NSString *ignordUrl in ignordUrls) {
//        if ([urlAbsoluteString rangeOfString:ignordUrl].length) {
//            return;
//        }
//    }
//    //弹出网络提示
//  if (!operation.error) {
//      if ([operation.responseObject objectForKey:@"msg"] && [[operation.responseObject objectForKey:@"msg"] length]) {
//          [KeyWindow showAlertMessage:[operation.responseObject objectForKey:@"msg"] callback:nil];
//      }
//  }
//  else {
//        if (operation.error.code == kCFURLErrorNotConnectedToInternet) {
//            [KeyWindow showAlertMessage:@"您已断开网络连接" callback:nil];
//        } else {
//            [KeyWindow showAlertMessage:@"服务器忙，请稍后再试" callback:nil];
//        }
//  }
}  

@end
