-- 邮箱注册/验证码那条路早已下线（账号是用户名 + 密码，没有邮箱），
-- 这两张表在代码里已经没有任何读写方，留着的只是一份没人看管的收件人与验证码残留。
-- 连同 0002/0005 给它们加的列和索引一起随表消失。
DROP TABLE IF EXISTS account_challenges;
DROP TABLE IF EXISTS account_mail;
