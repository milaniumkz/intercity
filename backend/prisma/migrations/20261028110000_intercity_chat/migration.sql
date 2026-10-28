CREATE TABLE "IntercityChatMessage" (
  "id" TEXT NOT NULL,
  "requestId" TEXT NOT NULL,
  "senderId" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IntercityChatMessage_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "IntercityChatMessage_requestId_createdAt_idx" ON "IntercityChatMessage"("requestId", "createdAt");
ALTER TABLE "IntercityChatMessage" ADD CONSTRAINT "IntercityChatMessage_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "IntercityRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "IntercityChatMessage" ADD CONSTRAINT "IntercityChatMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
