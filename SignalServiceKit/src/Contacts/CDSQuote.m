//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CDSQuote.h"

NS_ASSUME_NONNULL_BEGIN

@interface ByteParser : NSObject

@end

#pragma mark -

@interface ByteParser ()

@property (nonatomic, readonly) BOOL littleEndian;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic) NSUInteger cursor;
@property (nonatomic) BOOL hasError;

@end

#pragma mark -

@implementation ByteParser

- (instancetype)initWithData:(NSData *)data littleEndian:(BOOL)littleEndian
{
    if (self = [super init]) {
        _littleEndian = littleEndian;
        _data = data;
    }

    return self;
}

#pragma mark - Short

- (uint16_t)shortAtIndex:(NSUInteger)index
{
    uint16_t value;
    const size_t valueSize = sizeof(value);
    OWSAssert(valueSize == 2);
    if (index + valueSize > self.data.length) {
        self.hasError = YES;
        return 0;
    }
    [self.data getBytes:&value range:NSMakeRange(index, valueSize)];
    if (self.littleEndian) {
        return CFSwapInt16LittleToHost(value);
    } else {
        return CFSwapInt16BigToHost(value);
    }
}

- (uint16_t)nextShort
{
    uint16_t value = [self shortAtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark - Int

- (uint32_t)intAtIndex:(NSUInteger)index
{
    uint32_t value;
    const size_t valueSize = sizeof(value);
    OWSAssert(valueSize == 4);
    if (index + valueSize > self.data.length) {
        self.hasError = YES;
        return 0;
    }
    [self.data getBytes:&value range:NSMakeRange(index, valueSize)];
    if (self.littleEndian) {
        return CFSwapInt32LittleToHost(value);
    } else {
        return CFSwapInt32BigToHost(value);
    }
}

- (uint32_t)nextInt
{
    uint32_t value = [self intAtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark - Long

- (uint64_t)longAtIndex:(NSUInteger)index
{
    uint64_t value;
    const size_t valueSize = sizeof(value);
    OWSAssert(valueSize == 8);
    if (index + valueSize > self.data.length) {
        self.hasError = YES;
        return 0;
    }
    [self.data getBytes:&value range:NSMakeRange(index, valueSize)];
    if (self.littleEndian) {
        return CFSwapInt64LittleToHost(value);
    } else {
        return CFSwapInt64BigToHost(value);
    }
}

- (uint64_t)nextLong
{
    uint64_t value = [self longAtIndex:self.cursor];
    self.cursor += sizeof(value);
    return value;
}

#pragma mark -

- (BOOL)readZero:(NSUInteger)length
{
    NSData *_Nullable subdata = [self readBytes:length];
    if (!subdata) {
        return NO;
    }
    uint8_t bytes[length];
    [subdata getBytes:bytes range:NSMakeRange(0, length)];
    for (int i = 0; i < length; i++) {
        if (bytes[i] != 0) {
            return NO;
        }
    }
    return YES;
}

- (nullable NSData *)readBytes:(NSUInteger)length
{
    NSUInteger index = self.cursor;
    if (index + length > self.data.length) {
        self.hasError = YES;
        return nil;
    }
    NSData *_Nullable subdata = [self.data subdataWithRange:NSMakeRange(index, length)];
    self.cursor += length;
    return subdata;
}

@end

#pragma mark -

static const long SGX_FLAGS_INITTED = 0x0000000000000001L;
static const long SGX_FLAGS_DEBUG = 0x0000000000000002L;
static const long SGX_FLAGS_MODE64BIT = 0x0000000000000004L;
static const long SGX_FLAGS_PROVISION_KEY = 0x0000000000000004L;
static const long SGX_FLAGS_EINITTOKEN_KEY = 0x0000000000000004L;
static const long SGX_FLAGS_RESERVED = 0xFFFFFFFFFFFFFFC8L;
static const long SGX_XFRM_LEGACY = 0x0000000000000003L;
static const long SGX_XFRM_AVX = 0x0000000000000006L;
static const long SGX_XFRM_RESERVED = 0xFFFFFFFFFFFFFFF8L;

#pragma mark -

@interface CDSQuote ()

@property (nonatomic) uint16_t version;
@property (nonatomic) uint16_t signType;
@property (nonatomic) BOOL isSigLinkable;
@property (nonatomic) uint32_t gid;
@property (nonatomic) uint16_t qeSvn;
@property (nonatomic) uint16_t pceSvn;
@property (nonatomic) NSData *basename;
@property (nonatomic) NSData *cpuSvn;
@property (nonatomic) uint64_t flags;
@property (nonatomic) uint64_t xfrm;
@property (nonatomic) NSData *mrenclave;
@property (nonatomic) NSData *mrsigner;
@property (nonatomic) uint16_t isvProdId;
@property (nonatomic) uint16_t isvSvn;
@property (nonatomic) NSData *reportData;
@property (nonatomic) NSData *signature;

@end

#pragma mark -

@implementation CDSQuote

+ (nullable CDSQuote *)parseQuoteFromData:(NSData *)quoteData
{
    ByteParser *_Nullable parser = [[ByteParser alloc] initWithData:quoteData littleEndian:YES];

    uint16_t version = parser.nextShort;
    if (version < 1 || version > 2) {
        OWSProdLogAndFail(@"%@ unexpected quote version: %d", self.logTag, (int)version);
        return nil;
    }

    uint16_t signType = parser.nextShort;
    if ((signType & ~1) != 0) {
        OWSProdLogAndFail(@"%@ invalid signType: %d", self.logTag, (int)signType);
        return nil;
    }

    BOOL isSigLinkable = signType == 1;
    uint32_t gid = parser.nextInt;
    uint16_t qeSvn = parser.nextShort;

    uint16_t pceSvn = 0;
    if (version > 1) {
        pceSvn = parser.nextShort;
    } else {
        if (![parser readZero:2]) {
            OWSProdLogAndFail(@"%@ non-zero pceSvn.", self.logTag);
            return nil;
        }
    }

    if (![parser readZero:4]) {
        OWSProdLogAndFail(@"%@ non-zero xeid.", self.logTag);
        return nil;
    }

    NSData *_Nullable basename = [parser readBytes:32];
    if (!basename) {
        OWSProdLogAndFail(@"%@ couldn't read basename.", self.logTag);
        return nil;
    }

    // report_body

    NSData *_Nullable cpuSvn = [parser readBytes:16];
    if (!cpuSvn) {
        OWSProdLogAndFail(@"%@ couldn't read cpuSvn.", self.logTag);
        return nil;
    }
    if (![parser readZero:4]) {
        OWSProdLogAndFail(@"%@ non-zero misc_select.", self.logTag);
        return nil;
    }
    if (![parser readZero:28]) {
        OWSProdLogAndFail(@"%@ non-zero reserved1.", self.logTag);
        return nil;
    }

    uint64_t flags = parser.nextLong;
    if ((flags & SGX_FLAGS_RESERVED) != 0 || (flags & SGX_FLAGS_INITTED) == 0 || (flags & SGX_FLAGS_MODE64BIT) == 0) {
        OWSProdLogAndFail(@"%@ invalid flags.", self.logTag);
        return nil;
    }

    uint64_t xfrm = parser.nextLong;
    if ((xfrm & SGX_XFRM_RESERVED) != 0) {
        OWSProdLogAndFail(@"%@ invalid xfrm.", self.logTag);
        return nil;
    }

    NSData *_Nullable mrenclave = [parser readBytes:32];
    if (!mrenclave) {
        OWSProdLogAndFail(@"%@ couldn't read mrenclave.", self.logTag);
        return nil;
    }
    if (![parser readZero:32]) {
        OWSProdLogAndFail(@"%@ non-zero reserved2.", self.logTag);
        return nil;
    }
    NSData *_Nullable mrsigner = [parser readBytes:32];
    if (!mrsigner) {
        OWSProdLogAndFail(@"%@ couldn't read mrsigner.", self.logTag);
        return nil;
    }
    if (![parser readZero:96]) {
        OWSProdLogAndFail(@"%@ non-zero reserved3.", self.logTag);
        return nil;
    }
    uint16_t isvProdId = parser.nextShort;
    uint16_t isvSvn = parser.nextShort;
    if (![parser readZero:60]) {
        OWSProdLogAndFail(@"%@ non-zero reserved4.", self.logTag);
        return nil;
    }
    NSData *_Nullable reportData = [parser readBytes:64];
    if (!reportData) {
        OWSProdLogAndFail(@"%@ couldn't read reportData.", self.logTag);
        return nil;
    }

    // quote signature
    uint32_t signatureLength = parser.nextInt;
    if (signatureLength != quoteData.length - 436) {
        OWSProdLogAndFail(@"%@ invalid signatureLength.", self.logTag);
        return nil;
    }
    NSData *_Nullable signature = [parser readBytes:signatureLength];
    if (!signature) {
        OWSProdLogAndFail(@"%@ couldn't read signature.", self.logTag);
        return nil;
    }

    if (parser.hasError) {
        return nil;
    }

    CDSQuote *quote = [CDSQuote new];
    quote.version = version;
    quote.signType = signType;
    quote.isSigLinkable = isSigLinkable;
    quote.gid = gid;
    quote.qeSvn = qeSvn;
    quote.pceSvn = pceSvn;
    quote.basename = basename;
    quote.cpuSvn = cpuSvn;
    quote.flags = flags;
    quote.xfrm = xfrm;
    quote.mrenclave = mrenclave;
    quote.mrsigner = mrsigner;
    quote.isvProdId = isvProdId;
    quote.isvSvn = isvSvn;
    quote.reportData = reportData;
    quote.signature = signature;

    return quote;
}

@end

NS_ASSUME_NONNULL_END
