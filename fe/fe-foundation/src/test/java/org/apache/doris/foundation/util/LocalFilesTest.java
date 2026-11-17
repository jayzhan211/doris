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

package org.apache.doris.foundation.util;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

import java.io.File;
import java.util.Arrays;
import java.util.List;

public class LocalFilesTest {
    private static final List<String> PATHS = Arrays.asList(
            "", "/", "//a", "/a//b/", "a/b/", "/x/../y", "s3://bucket/key", "edits.1", "目錄/文件", "a\u0000b");

    @Test
    public void testFileMatchesFileConstructor() {
        for (String path : PATHS) {
            Assertions.assertEquals(new File(path), LocalFiles.file(path), path);
            Assertions.assertEquals(new File(path).getPath(), LocalFiles.file(new StringBuilder(path)).getPath(), path);
        }
    }

    @Test
    public void testChildFileMatchesFileConstructor() {
        for (String parent : PATHS) {
            for (String child : Arrays.asList("edits.1", "/abs", "", "子")) {
                Assertions.assertEquals(new File(parent, child), LocalFiles.file(parent, child), parent + "|" + child);
                Assertions.assertEquals(new File(new File(parent), child),
                        LocalFiles.file(new File(parent), child), parent + "|" + child);
            }
        }
    }

    @Test
    public void testNullBehavesLikeFileConstructor() {
        Assertions.assertThrows(NullPointerException.class, () -> new File((String) null));
        Assertions.assertThrows(NullPointerException.class, () -> LocalFiles.file((CharSequence) null));
    }
}
