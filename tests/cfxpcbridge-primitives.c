// Round trips for the XPC primitive types exposed by the CoreFoundation/XPC bridge.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFXPCBridge.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

static int failures;

static void check(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

static void test_double(void)
{
	xpc_object_t xpc = xpc_double_create(3.5);
	CFTypeRef cf = _CFXPCCreateCFObjectFromXPCObject(xpc);
	check("double: converted to CFNumber", cf != NULL && CFGetTypeID(cf) == CFNumberGetTypeID());
	if (cf) {
		double value = 0;
		check("double: CFNumber is a floating point number", CFNumberIsFloatType((CFNumberRef)cf));
		check("double: value preserved", CFNumberGetValue((CFNumberRef)cf, kCFNumberDoubleType, &value) && value == 3.5);
		xpc_object_t roundTrip = _CFXPCCreateXPCObjectFromCFObject(cf);
		check("double: converted back to XPC", roundTrip != NULL && xpc_get_type(roundTrip) == XPC_TYPE_DOUBLE);
		if (roundTrip) {
			check("double: round-tripped value preserved", xpc_double_get_value(roundTrip) == 3.5);
			xpc_release(roundTrip);
		}
		CFRelease(cf);
	}
	xpc_release(xpc);
}

static void test_date(void)
{
	const int64_t oneDayNanoseconds = INT64_C(86400) * INT64_C(1000000000);
	xpc_object_t xpc = xpc_date_create(oneDayNanoseconds);
	CFTypeRef cf = _CFXPCCreateCFObjectFromXPCObject(xpc);
	check("date: converted to CFDate", cf != NULL && CFGetTypeID(cf) == CFDateGetTypeID());
	if (cf) {
		CFAbsoluteTime value = CFDateGetAbsoluteTime((CFDateRef)cf);
		check("date: Unix nanoseconds converted to the CF epoch", fabs(value - 86400.0) < 1e-6);
		xpc_object_t roundTrip = _CFXPCCreateXPCObjectFromCFObject(cf);
		check("date: converted back to XPC", roundTrip != NULL && xpc_get_type(roundTrip) == XPC_TYPE_DATE);
		if (roundTrip) {
			check("date: round-tripped value preserved", xpc_date_get_value(roundTrip) == oneDayNanoseconds);
			xpc_release(roundTrip);
		}
		CFRelease(cf);
	}
	xpc_release(xpc);
}

static void test_uuid(void)
{
	const uint8_t bytes[16] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
	                            0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff };
	xpc_object_t xpc = xpc_uuid_create(bytes);
	CFTypeRef cf = _CFXPCCreateCFObjectFromXPCObject(xpc);
	check("uuid: converted to CFUUID", cf != NULL && CFGetTypeID(cf) == CFUUIDGetTypeID());
	if (cf) {
		CFUUIDBytes value = CFUUIDGetUUIDBytes((CFUUIDRef)cf);
		int bytesMatch = value.byte0 == bytes[0] && value.byte1 == bytes[1] &&
		                 value.byte2 == bytes[2] && value.byte3 == bytes[3] &&
		                 value.byte4 == bytes[4] && value.byte5 == bytes[5] &&
		                 value.byte6 == bytes[6] && value.byte7 == bytes[7] &&
		                 value.byte8 == bytes[8] && value.byte9 == bytes[9] &&
		                 value.byte10 == bytes[10] && value.byte11 == bytes[11] &&
		                 value.byte12 == bytes[12] && value.byte13 == bytes[13] &&
		                 value.byte14 == bytes[14] && value.byte15 == bytes[15];
		check("uuid: bytes preserved", bytesMatch);
		xpc_object_t roundTrip = _CFXPCCreateXPCObjectFromCFObject(cf);
		check("uuid: converted back to XPC", roundTrip != NULL && xpc_get_type(roundTrip) == XPC_TYPE_UUID);
		if (roundTrip) {
			const uint8_t *roundTripBytes = xpc_uuid_get_bytes(roundTrip);
			int roundTripMatches = roundTripBytes != NULL;
			for (int i = 0; roundTripMatches && i < 16; i++)
				roundTripMatches = roundTripBytes[i] == bytes[i];
			check("uuid: round-tripped bytes preserved", roundTripMatches);
			xpc_release(roundTrip);
		}
		CFRelease(cf);
	}
	xpc_release(xpc);
}

int main(void)
{
	test_double();
	test_date();
	test_uuid();
	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
