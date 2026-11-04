-- Pause new driver withholding until government integration; preserve history.
INSERT INTO "AppSettings" (id,key,value,"updatedAt")
VALUES (gen_random_uuid()::text,'driverTaxIntegrationPaused','true',NOW())
ON CONFLICT (key) DO UPDATE SET value='true',"updatedAt"=NOW();
INSERT INTO "AppSettings" (id,key,value,"updatedAt")
VALUES (gen_random_uuid()::text,'iosDistributionMode','web',NOW())
ON CONFLICT (key) DO UPDATE SET value='web',"updatedAt"=NOW();
INSERT INTO "AppSettings" (id,key,value,"updatedAt")
VALUES (gen_random_uuid()::text,'googlePlayUrl','https://play.google.com/store/apps/details?id=com.milanium.intercity',NOW())
ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value,"updatedAt"=NOW() WHERE "AppSettings".value='';
