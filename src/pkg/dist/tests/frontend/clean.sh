#! /usr/bin/env atf-sh

. $(atf_get_srcdir)/test_environment.sh

tests_init \
	basic \
	clean_all_no_repo_db \
	clean_no_repo_db

basic_body() {
	atf_check -s exit:0 sh ${RESOURCEDIR}/test_subr.sh new_pkg "test" "test" "1"

	atf_check \
		-o empty \
		-e empty \
		-s exit:0 \
		pkg create -M test.ucl
	mkdir -p ${TMPDIR}/target
	atf_check \
		-e empty \
		-o ignore \
		-s exit:0 \
		pkg -o REPOS_DIR=/dev/null -r ${TMPDIR}/target install -qfy ${TMPDIR}/test-1.pkg

	atf_check -s exit:0 sh ${RESOURCEDIR}/test_subr.sh new_pkg "test" "test" "2"

	atf_check \
		-o empty \
		-e empty \
		-s exit:0 \
		pkg create -M test.ucl
	atf_check \
		-o ignore \
		-e empty \
		-s exit:0 \
		pkg repo .
	mkdir reposconf
	cat <<EOF >> reposconf/repo.conf
local: {
	url: file:///${TMPDIR},
	enabled: true
}
EOF
	atf_check \
		-e empty \
		-o ignore \
		-s exit:0 \
		pkg -o REPOS_DIR="${TMPDIR}/reposconf" update

	mkdir cache
	mv test-* cache
	atf_check \
		-e empty \
		-o match:"test-.\.pkg" \
		-s exit:0 \
		pkg -C /dev/null -o PKG_CACHEDIR=${TMPDIR}/cache -o REPOS_DIR="${TMPDIR}/reposconf" clean -n
}

clean_all_no_repo_db_body() {
	# pkg clean -a should work even without any repo database
	mkdir -p reposconf cache
	cat > reposconf/repo.conf << EOF
testrepo: {
    url: "file:///nonexistent",
    enabled: true
}
EOF
	echo "fake" > cache/test-1~abc123.pkg

	atf_check \
		-o match:"test-1" \
		-e empty \
		-s exit:0 \
		pkg -o REPOS_DIR="${TMPDIR}/reposconf" -o PKG_CACHEDIR=${TMPDIR}/cache clean -an
}

clean_no_repo_db_body() {
	# pkg clean (without -a) should treat all cached files as obsolete
	# when no repo database exists, instead of erroring out
	mkdir -p reposconf cache
	cat > reposconf/repo.conf << EOF
testrepo: {
    url: "file:///nonexistent",
    enabled: true
}
EOF
	echo "fake" > cache/test-1~abc123.pkg

	atf_check \
		-o match:"test-1" \
		-e empty \
		-s exit:0 \
		pkg -o REPOS_DIR="${TMPDIR}/reposconf" -o PKG_CACHEDIR=${TMPDIR}/cache clean -n
}
