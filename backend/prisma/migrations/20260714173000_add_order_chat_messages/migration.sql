CREATE TABLE IF NOT EXISTS "OrderChatMessage" (
  "id" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "senderId" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "OrderChatMessage_pkey" PRIMARY KEY ("id")
);

DO $$ BEGIN
  ALTER TABLE "OrderChatMessage" ADD CONSTRAINT "OrderChatMessage_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "OrderChatMessage" ADD CONSTRAINT "OrderChatMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "OrderChatMessage_orderId_createdAt_idx" ON "OrderChatMessage"("orderId", "createdAt");
CREATE INDEX IF NOT EXISTS "OrderChatMessage_senderId_createdAt_idx" ON "OrderChatMessage"("senderId", "createdAt");
