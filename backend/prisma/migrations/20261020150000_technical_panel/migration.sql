-- AlterTable
ALTER TABLE "User" ADD COLUMN     "authVersion" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "blockedAt" TIMESTAMP(3),
ADD COLUMN     "mustChangePassword" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "TechAccount" (
    "id" TEXT NOT NULL,
    "login" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "permissions" TEXT[],
    "disabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechSession" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechEvent" (
    "id" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "userId" TEXT,
    "actorId" TEXT,
    "sessionId" TEXT,
    "requestId" TEXT NOT NULL,
    "objectId" TEXT,
    "action" TEXT NOT NULL,
    "stage" TEXT NOT NULL,
    "result" TEXT NOT NULL,
    "status" INTEGER,
    "durationMs" INTEGER,
    "message" TEXT,
    "ip" TEXT,
    "client" JSONB,
    "details" JSONB,
    "issueId" TEXT,

    CONSTRAINT "TechEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechIssue" (
    "id" TEXT NOT NULL,
    "fingerprint" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "severity" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'NEW',
    "count" INTEGER NOT NULL DEFAULT 1,
    "firstAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "assignedTo" TEXT,
    "confirmedCause" TEXT,
    "hypothesis" TEXT,
    "verification" TEXT,
    "fixedVersion" TEXT,
    "mutedUntil" TIMESTAMP(3),

    CONSTRAINT "TechIssue_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechComment" (
    "id" TEXT NOT NULL,
    "issueId" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechComment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechFile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "requestId" TEXT NOT NULL,
    "objectId" TEXT,
    "docType" TEXT NOT NULL,
    "path" TEXT NOT NULL,
    "mime" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "sha256" TEXT NOT NULL,
    "verdict" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "algorithm" TEXT NOT NULL,
    "metrics" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "TechFile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechAudit" (
    "seq" BIGSERIAL NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actorId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "objectId" TEXT,
    "data" JSONB NOT NULL,
    "previousHash" TEXT NOT NULL,
    "hash" TEXT NOT NULL,

    CONSTRAINT "TechAudit_pkey" PRIMARY KEY ("seq")
);

-- CreateTable
CREATE TABLE "TechNotification" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "issueId" TEXT NOT NULL,
    "severity" TEXT NOT NULL,
    "acknowledgedAt" TIMESTAMP(3),
    "pushAt" TIMESTAMP(3),
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechNotification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechPush" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "endpoint" TEXT NOT NULL,
    "subscription" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechPush_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechLoginAttempt" (
    "key" TEXT NOT NULL,
    "failures" INTEGER NOT NULL DEFAULT 0,
    "until" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TechLoginAttempt_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "TechReport" (
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "version" TEXT,
    "details" JSONB,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TechRule" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TechRule_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE UNIQUE INDEX "TechAccount_login_key" ON "TechAccount"("login");

-- CreateIndex
CREATE UNIQUE INDEX "TechSession_tokenHash_key" ON "TechSession"("tokenHash");

-- CreateIndex
CREATE INDEX "TechSession_accountId_expiresAt_idx" ON "TechSession"("accountId", "expiresAt");

-- CreateIndex
CREATE INDEX "TechEvent_at_id_idx" ON "TechEvent"("at", "id");

-- CreateIndex
CREATE INDEX "TechEvent_userId_at_id_idx" ON "TechEvent"("userId", "at", "id");

-- CreateIndex
CREATE INDEX "TechEvent_requestId_at_idx" ON "TechEvent"("requestId", "at");

-- CreateIndex
CREATE INDEX "TechEvent_sessionId_at_idx" ON "TechEvent"("sessionId", "at");

-- CreateIndex
CREATE INDEX "TechEvent_objectId_at_idx" ON "TechEvent"("objectId", "at");

-- CreateIndex
CREATE INDEX "TechEvent_issueId_at_idx" ON "TechEvent"("issueId", "at");

-- CreateIndex
CREATE INDEX "TechEvent_result_at_idx" ON "TechEvent"("result", "at");

-- CreateIndex
CREATE UNIQUE INDEX "TechIssue_fingerprint_key" ON "TechIssue"("fingerprint");

-- CreateIndex
CREATE INDEX "TechIssue_status_lastAt_idx" ON "TechIssue"("status", "lastAt");

-- CreateIndex
CREATE INDEX "TechComment_issueId_createdAt_idx" ON "TechComment"("issueId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "TechFile_path_key" ON "TechFile"("path");

-- CreateIndex
CREATE INDEX "TechFile_userId_createdAt_idx" ON "TechFile"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "TechFile_requestId_idx" ON "TechFile"("requestId");

-- CreateIndex
CREATE INDEX "TechFile_objectId_createdAt_idx" ON "TechFile"("objectId", "createdAt");

-- CreateIndex
CREATE INDEX "TechFile_verdict_createdAt_idx" ON "TechFile"("verdict", "createdAt");

-- CreateIndex
CREATE INDEX "TechNotification_accountId_createdAt_idx" ON "TechNotification"("accountId", "createdAt");

-- CreateIndex
CREATE INDEX "TechNotification_pushAt_nextAttemptAt_idx" ON "TechNotification"("pushAt", "nextAttemptAt");

-- CreateIndex
CREATE UNIQUE INDEX "TechNotification_accountId_issueId_key" ON "TechNotification"("accountId", "issueId");

-- CreateIndex
CREATE UNIQUE INDEX "TechPush_endpoint_key" ON "TechPush"("endpoint");

-- CreateIndex
CREATE INDEX "TechReport_kind_at_idx" ON "TechReport"("kind", "at");


-- The application has no endpoint to rewrite audit history; database triggers also
-- reject accidental updates/deletes. A database superuser can still bypass them.
CREATE FUNCTION tech_audit_append_only() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'Technical audit is append-only'; END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER tech_audit_immutable BEFORE UPDATE OR DELETE ON "TechAudit"
FOR EACH ROW EXECUTE FUNCTION tech_audit_append_only();
