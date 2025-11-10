-- -------------------------------------------------------------------
-- ----------------------- ATIVIDADE ---------------------------------
-- -------------------------------------------------------------------

-- 1) O que você achou da forma como o banco foi populado (arquivo sala-dml.sql)?
--      Há formas melhores de ter feito esse preenchimento? Como?
--      Como melhorar esse script usando comandos TCL?
--      Obs.: Essa questão é discursiva, não envie códigos nela.

/*
O arquivo sala-dml.sql faz o banco com vários INSERTs simples.
Isso é funcional, mas não otimizado. Poderia ser melhorado agrupando os INSERTs em transações
com START TRANSACTION e COMMIT para garantir atomicidade e segurança.
Também seria possível usar LOAD DATA INFILE para inserções em massa ou criar procedimentos
para popular automaticamente os dados de teste.
Comandos TCL (Transaction Control Language) como SAVEPOINT e ROLLBACK poderiam ser usados
para evitar inconsistências caso um dos INSERTs falhe.
*/

-- -------------------------------------------------------------------
-- 2) Criar um índice para CPF na tabela Pessoa
-- -------------------------------------------------------------------
CREATE INDEX idx_pessoa_cpf ON Pessoa(CPF);

-- -------------------------------------------------------------------
-- 3) Criar FULLTEXT INDEX em Avaliacao.ocorrencia e tipo_prova e buscar por "cola" na P3
-- -------------------------------------------------------------------
ALTER TABLE Avaliacao
  ADD FULLTEXT INDEX ft_ocorrencia_tipo (ocorrencia, tipo_prova);

SELECT *
FROM Avaliacao
WHERE MATCH(ocorrencia, tipo_prova)
      AGAINST('+cola +P3' IN BOOLEAN MODE);

-- -------------------------------------------------------------------
-- 4) Benefícios e cuidados com índices
-- -------------------------------------------------------------------
/*
Benefícios:
- Melhora a velocidade de consultas que usam o campo indexado.
- O FULLTEXT permite buscas rápidas em campos grandes de texto (como ocorrências).
Cuidados:
- Índices aumentam o uso de espaço em disco.
- Inserções e atualizações ficam ligeiramente mais lentas.
- FULLTEXT depende de configurações (idioma, stopwords).
- Criação excessiva de índices pode piorar a performance global.
*/

-- -------------------------------------------------------------------
-- 5) VIEW: alunos ativos (sem status disciplinar) com ocorrências em avaliações
-- -------------------------------------------------------------------
CREATE VIEW vw_alunos_ativos_com_ocorrencias AS
SELECT
  a.matricula,
  p.nome,
  COUNT(av.ID) AS qtd_ocorrencias
FROM Aluno a
JOIN Pessoa p ON p.ID = a.pessoa_id
JOIN Aluno_Turma atur ON atur.aluno_mat = a.matricula
JOIN Avaliacao av ON av.aluno_turma_id = atur.ID
WHERE a.status = 'ativo'
  AND av.ocorrencia IS NOT NULL
  AND TRIM(av.ocorrencia) <> ''
GROUP BY a.matricula, p.nome;

-- -------------------------------------------------------------------
-- 6) VIEWs: professor + pessoa / aluno + pessoa
-- -------------------------------------------------------------------
CREATE VIEW vw_professor_dados AS
SELECT
  pr.matricula AS matricula_professor,
  p.nome,
  p.CPF,
  p.end_cidade,
  p.end_uf_sigla,
  pr.ativo
FROM Professor pr
JOIN Pessoa p ON p.ID = pr.pessoa_id;

CREATE VIEW vw_aluno_dados AS
SELECT
  a.matricula AS matricula_aluno,
  p.nome,
  p.CPF,
  p.end_cidade,
  p.end_uf_sigla,
  a.status
FROM Aluno a
JOIN Pessoa p ON p.ID = a.pessoa_id;

-- -------------------------------------------------------------------
-- 7) ROLE Secretaria (sem permissão de DELETE)
-- -------------------------------------------------------------------
CREATE ROLE 'Secretaria';
GRANT SELECT, INSERT, UPDATE, CREATE, ALTER, INDEX, EXECUTE, SHOW VIEW, TRIGGER
  ON SalaDeAula.* TO 'Secretaria';

-- -------------------------------------------------------------------
-- 8) Usuário Maria com acesso de Secretaria
-- -------------------------------------------------------------------
CREATE USER 'maria'@'%' IDENTIFIED BY 'SenhaForte123!';
GRANT 'Secretaria' TO 'maria'@'%';
SET DEFAULT ROLE 'Secretaria' TO 'maria'@'%';

-- -------------------------------------------------------------------
-- 9) TRIGGER: zera nota se for inserida ocorrência que justifique isso
-- -------------------------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_avaliacao_before_insert
BEFORE INSERT ON Avaliacao
FOR EACH ROW
BEGIN
  IF NEW.ocorrencia IS NOT NULL THEN
    IF LOWER(NEW.ocorrencia) LIKE '%cola%' OR
       LOWER(NEW.ocorrencia) LIKE '%plágio%' OR
       LOWER(NEW.ocorrencia) LIKE '%plagio%' OR
       LOWER(NEW.ocorrencia) LIKE '%cópia%' THEN
      SET NEW.nota = 0.0;
    END IF;
  END IF;
END$$
DELIMITER ;

-- -------------------------------------------------------------------
-- 10) TRIGGER: zera nota ao atualizar e adicionar ocorrência que justifique isso
-- -------------------------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_avaliacao_before_update
BEFORE UPDATE ON Avaliacao
FOR EACH ROW
BEGIN
  IF NEW.ocorrencia IS NOT NULL AND (
     LOWER(NEW.ocorrencia) LIKE '%cola%' OR
     LOWER(NEW.ocorrencia) LIKE '%plágio%' OR
     LOWER(NEW.ocorrencia) LIKE '%plagio%' OR
     LOWER(NEW.ocorrencia) LIKE '%cópia%') THEN
     SET NEW.nota = 0.0;
  END IF;
END$$
DELIMITER ;

-- -------------------------------------------------------------------
-- 11) FUNCTION: calcular nota final por aluno e turma
-- -------------------------------------------------------------------
DELIMITER $$
CREATE FUNCTION fn_nota_final(p_aluno_turma INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
  DECLARE media DECIMAL(5,2);
  SELECT AVG(nota) INTO media
  FROM Avaliacao
  WHERE aluno_turma_id = p_aluno_turma;
  RETURN IFNULL(media, 0.0);
END$$
DELIMITER ;

-- -------------------------------------------------------------------
-- 12) PROCEDURE: suspender ou expulsar aluno por número de ocorrências
-- -------------------------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_avaliar_ocorrencias(IN p_matricula VARCHAR(10))
BEGIN
  DECLARE qtd INT DEFAULT 0;
  SELECT COUNT(*) INTO qtd
  FROM Avaliacao av
  JOIN Aluno_Turma atur ON atur.ID = av.aluno_turma_id
  WHERE atur.aluno_mat = p_matricula
    AND av.ocorrencia IS NOT NULL
    AND TRIM(av.ocorrencia) <> '';

  IF qtd >= 9 THEN
    UPDATE Aluno SET status = 'expulso' WHERE matricula = p_matricula;
  ELSEIF qtd >= 3 THEN
    UPDATE Aluno SET status = 'suspenso' WHERE matricula = p_matricula;
  END IF;
END$$
DELIMITER ;
