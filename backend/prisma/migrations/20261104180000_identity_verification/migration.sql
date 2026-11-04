-- CreateTable
CREATE TABLE "BiometricProfile" (
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'VERIFIED',
    "model" TEXT NOT NULL,
    "template" TEXT NOT NULL,
    "referencePath" TEXT NOT NULL,
    "consentVersion" TEXT NOT NULL,
    "driverConsent" BOOLEAN NOT NULL DEFAULT false,
    "driverDocumentHash" TEXT,
    "vehicleData" JSONB,
    "vehicleDocumentHash" TEXT,
    "enrolledAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BiometricProfile_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "BiometricChallenge" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "videoSignature" TEXT,
    "videoDigest" TEXT,
    "subjectHash" TEXT NOT NULL,
    "ipHash" TEXT NOT NULL,
    "purpose" TEXT NOT NULL,
    "secretHash" TEXT NOT NULL,
    "actions" JSONB NOT NULL,
    "authVersion" INTEGER NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "claimedAt" TIMESTAMP(3),
    "status" TEXT NOT NULL DEFAULT 'READY',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "documentInfo" JSONB,
    "candidate" TEXT,
    "referencePath" TEXT,
    "secondaryPath" TEXT,
    "videoPath" TEXT,
    "model" TEXT,
    "reason" TEXT,
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "notifiedAt" TIMESTAMP(3),
    "pushAttempts" INTEGER NOT NULL DEFAULT 0,
    "consentVersion" TEXT NOT NULL,
    "driverConsent" BOOLEAN NOT NULL DEFAULT false,
    "resetHash" TEXT,
    "resetExpiresAt" TIMESTAMP(3),
    "consumedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BiometricChallenge_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdminWebPushSubscription" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "endpoint" TEXT NOT NULL,
    "subscription" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdminWebPushSubscription_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "BiometricChallenge_videoDigest_key" ON "BiometricChallenge"("videoDigest");

-- CreateIndex
CREATE UNIQUE INDEX "BiometricChallenge_resetHash_key" ON "BiometricChallenge"("resetHash");

-- CreateIndex
CREATE INDEX "BiometricChallenge_subjectHash_createdAt_idx" ON "BiometricChallenge"("subjectHash", "createdAt");

-- CreateIndex
CREATE INDEX "BiometricChallenge_ipHash_createdAt_idx" ON "BiometricChallenge"("ipHash", "createdAt");

-- CreateIndex
CREATE INDEX "BiometricChallenge_userId_createdAt_idx" ON "BiometricChallenge"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "BiometricChallenge_status_createdAt_idx" ON "BiometricChallenge"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "AdminWebPushSubscription_endpoint_key" ON "AdminWebPushSubscription"("endpoint");

-- AddForeignKey
ALTER TABLE "BiometricProfile" ADD CONSTRAINT "BiometricProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BiometricChallenge" ADD CONSTRAINT "BiometricChallenge_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdminWebPushSubscription" ADD CONSTRAINT "AdminWebPushSubscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "AppSettings" (id,key,value,"updatedAt") VALUES(gen_random_uuid()::text,'identityVerificationEnabled','true',NOW()) ON CONFLICT(key) DO NOTHING;
INSERT INTO "AdminPermission" (id,key,module,action,description,"createdAt","updatedAt") VALUES(gen_random_uuid()::text,'identity.review','identity','review','Проверка личности и защищённые биометрические материалы',NOW(),NOW()) ON CONFLICT(key) DO NOTHING;
