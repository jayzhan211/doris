// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package org.apache.doris.datasource.jdbc.client;

import org.junit.Assert;
import org.junit.Test;
import org.mockito.Mockito;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Remote database and table names reach the Oracle metadata queries as bound parameters, never as SQL text,
 * so a name containing a quote cannot change the query.
 */
public class JdbcOracleClientBindingTest {
    private static final String TABLE = "t' OR '1'='1";

    private final List<String> preparedSql = new ArrayList<>();
    private final List<String> boundStrings = new ArrayList<>();

    @Test
    public void testTableExistenceBindsNames() throws Exception {
        JdbcOracleClient client = clientWithRecordingConnection();

        Assert.assertFalse(client.isTableExist("REMOTE", TABLE));

        Assert.assertEquals(Collections.singletonList("SELECT SYNONYM_NAME as TABLE_NAME, TABLE_OWNER as "
                + "BASE_TABLE_OWNER, TABLE_NAME as BASE_TABLE_NAME FROM ALL_SYNONYMS "
                + "WHERE OWNER = ? AND SYNONYM_NAME = ?"), preparedSql);
        Assert.assertEquals(Arrays.asList("REMOTE", TABLE), boundStrings);
    }

    @Test
    public void testSynonymCheckBindsNames() throws Exception {
        JdbcOracleClient client = clientWithRecordingConnection();

        Assert.assertTrue(client.getJdbcColumnsInfo("REMOTE", TABLE).isEmpty());

        Assert.assertEquals(Collections.singletonList(
                "SELECT OBJECT_TYPE FROM ALL_OBJECTS WHERE OBJECT_NAME = ? AND OWNER = ?"), preparedSql);
        Assert.assertEquals(Arrays.asList(TABLE, "REMOTE"), boundStrings);
    }

    private JdbcOracleClient clientWithRecordingConnection() throws Exception {
        ResultSet empty = Mockito.mock(ResultSet.class);
        Mockito.when(empty.next()).thenReturn(false);
        DatabaseMetaData metaData = Mockito.mock(DatabaseMetaData.class);
        Mockito.when(metaData.getTables(Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any())).thenReturn(empty);
        Mockito.when(metaData.getColumns(Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any()))
                .thenReturn(empty);
        PreparedStatement statement = Mockito.mock(PreparedStatement.class);
        Mockito.doAnswer(invocation -> boundStrings.add(invocation.getArgument(1)))
                .when(statement).setString(Mockito.anyInt(), Mockito.anyString());
        Mockito.when(statement.executeQuery()).thenReturn(empty);
        Connection connection = Mockito.mock(Connection.class);
        Mockito.when(connection.getMetaData()).thenReturn(metaData);
        Mockito.when(connection.prepareStatement(Mockito.anyString())).thenAnswer(invocation -> {
            preparedSql.add(invocation.getArgument(0));
            return statement;
        });
        Mockito.when(connection.createStatement()).thenThrow(new AssertionError("metadata query must bind names"));

        JdbcOracleClient client = Mockito.mock(JdbcOracleClient.class, Mockito.CALLS_REAL_METHODS);
        Mockito.doReturn(connection).when(client).getConnection();
        return client;
    }
}
