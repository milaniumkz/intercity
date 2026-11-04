-- Initial enrollment is automatic; existing uncertain captures must be retaken.
UPDATE "BiometricChallenge" SET status='REJECTED', reason='Первичная проверка теперь автоматическая. Запишите новое видео по голосовым подсказкам.' WHERE purpose='ENROLL' AND status='REVIEW';
