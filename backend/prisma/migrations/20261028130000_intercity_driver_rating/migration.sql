ALTER TABLE "IntercityRequest" ADD COLUMN "driverRating" INTEGER, ADD COLUMN "driverRatingStatus" TEXT NOT NULL DEFAULT 'COUNTED', ADD COLUMN "driverRatingReason" TEXT;
ALTER TABLE "Complaint" ADD COLUMN "intercityRequestId" TEXT;
ALTER TABLE "Complaint" ADD CONSTRAINT "Complaint_intercityRequestId_fkey" FOREIGN KEY ("intercityRequestId") REFERENCES "IntercityRequest"("id") ON DELETE SET NULL ON UPDATE CASCADE;
