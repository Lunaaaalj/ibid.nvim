-- Minimal Zotero-shaped schema exercising the production aggregate query.
CREATE TABLE itemTypes (itemTypeID INTEGER PRIMARY KEY, typeName TEXT);
CREATE TABLE items (itemID INTEGER PRIMARY KEY, key TEXT, libraryID INTEGER, itemTypeID INTEGER, dateAdded TEXT, dateModified TEXT);
CREATE TABLE fields (fieldID INTEGER PRIMARY KEY, fieldName TEXT);
CREATE TABLE itemDataValues (valueID INTEGER PRIMARY KEY, value TEXT);
CREATE TABLE itemData (itemID INTEGER, fieldID INTEGER, valueID INTEGER);
CREATE TABLE creators (creatorID INTEGER PRIMARY KEY, lastName TEXT, firstName TEXT);
CREATE TABLE creatorTypes (creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT);
CREATE TABLE itemCreators (itemID INTEGER, creatorID INTEGER, creatorTypeID INTEGER, orderIndex INTEGER);
CREATE TABLE tags (tagID INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE itemTags (itemID INTEGER, tagID INTEGER);
CREATE TABLE collections (collectionID INTEGER PRIMARY KEY, collectionName TEXT, parentCollectionID INTEGER, key TEXT, libraryID INTEGER);
CREATE TABLE collectionItems (collectionID INTEGER, itemID INTEGER);
CREATE TABLE itemAttachments (itemID INTEGER PRIMARY KEY, parentItemID INTEGER, contentType TEXT, path TEXT, linkMode INTEGER);
CREATE TABLE deletedItems (itemID INTEGER PRIMARY KEY);
CREATE TABLE groups (libraryID INTEGER PRIMARY KEY, groupID INTEGER, name TEXT);
INSERT INTO itemTypes VALUES (1,'journalArticle'),(2,'book'),(3,'attachment'),(4,'note'),(5,'annotation');
INSERT INTO items VALUES
 (1,'ARTICLE1',1,1,'2020-01-01 00:00:00','2024-01-01 00:00:00'),
 (2,'GROUPBK1',2,2,'2021-01-01 00:00:00','2024-02-01 00:00:00'),
 (3,'EMPTY001',1,2,'2022-01-01 00:00:00','2024-03-01 00:00:00'),
 (4,'DELETED1',1,1,'2023-01-01 00:00:00','2024-01-01 00:00:00'),
 (10,'PDF00001',1,3,'2020-01-01 00:00:00','2024-01-01 00:00:00'),
 (11,'PDFDEL01',1,3,'2020-01-01 00:00:00','2024-01-01 00:00:00'),
 (12,'LINK0001',2,3,'2020-01-01 00:00:00','2024-01-01 00:00:00'),
 (13,'NOTE0001',1,4,'2020-01-01 00:00:00','2024-01-01 00:00:00'),
 (14,'ANNOT001',1,5,'2020-01-01 00:00:00','2024-01-01 00:00:00');
INSERT INTO fields VALUES (1,'title'),(2,'citationKey'),(3,'date'),(4,'DOI'),(5,'abstractNote'),(6,'publicationTitle'),(7,'publisher');
INSERT INTO itemDataValues VALUES (1,'A careful study'),(2,'doe2020'),(3,'2020-00-00 2020'),(4,'10.1234/example'),(5,'An abstract.'),(6,'Journal of Fixtures'),(7,'Group handbook'),(8,'group2021'),(9,'2021'),(10,'Fixture Press'),(11,'Full text');
INSERT INTO itemData VALUES (1,1,1),(1,2,2),(1,3,3),(1,4,4),(1,5,5),(1,6,6),(2,1,7),(2,2,8),(2,3,9),(2,7,10),(10,1,11);
INSERT INTO creators VALUES (1,'Doe','Jane'),(2,'Roe','Richard'),(3,'Ignored','Editor'),(4,'','Research Council');
INSERT INTO creatorTypes VALUES (1,'author'),(2,'editor');
-- Deliberately insert authors out of display order.
INSERT INTO itemCreators VALUES (1,2,1,1),(1,1,1,0),(1,3,2,2),(2,4,2,0);
INSERT INTO tags VALUES (1,'methods'),(2,'review');
INSERT INTO itemTags VALUES (1,1),(1,2);
INSERT INTO collections VALUES (1,'Root',NULL,'COLROOT1',1),(2,'Child',1,'COLCHILD',1),(3,'Group shelf',NULL,'COLGROUP',2);
INSERT INTO collectionItems VALUES (2,1),(3,2);
INSERT INTO groups VALUES (2,42,'Fixture Group');
INSERT INTO itemAttachments VALUES (10,1,'application/pdf','storage:paper.pdf',0),(11,1,'application/pdf','storage:deleted.pdf',0),(12,2,'application/pdf','/fixture/linked.pdf',2);
INSERT INTO deletedItems VALUES (4),(11);
