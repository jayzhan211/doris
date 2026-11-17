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

import java.io.File;

/**
 * Builds {@link File} objects for local paths exactly as the {@code File} constructors do.
 *
 * <p>Use these instead of {@code java.nio.file.Path.of(..).toFile()} when the old code called a
 * {@code File} constructor: {@code Path.of} throws {@code InvalidPathException} for characters the
 * JVM's file-name encoding ({@code sun.jnu.encoding}, taken from the process locale) cannot represent,
 * for example any non-ASCII character under a {@code C} locale, while {@code new File} accepts them.</p>
 */
public final class LocalFiles {
    private LocalFiles() {
    }

    /** Same as {@code new File(path)}. */
    public static File file(CharSequence path) {
        return new File(path.toString());
    }

    /** Same as {@code new File(parent, child)}. */
    public static File file(File parent, CharSequence child) {
        return new File(parent, child.toString());
    }

    /** Same as {@code new File(parent, child)}. */
    public static File file(CharSequence parent, CharSequence child) {
        return new File(parent.toString(), child.toString());
    }
}
