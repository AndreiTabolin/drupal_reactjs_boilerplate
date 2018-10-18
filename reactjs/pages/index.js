import React from 'react';
import PropTypes from 'prop-types';
import { Container, Row, Col } from 'reactstrap';
import * as userApi from '../api/user';

class HomePage extends React.Component {
  static async getInitialProps({ superagent }) {
    let initialProps = {
      users: [],
      statusCode: 200,
    };

    try {
      // Load all users from the backend.
      initialProps = await userApi.getAll(superagent);
    } catch (e) {
      // Pass status code as internal properly. It is being checked inside of
      // render() method of _app.js.
      initialProps.statusCode = 500;
    }

    return initialProps;
  }

  render() {
    const { users } = this.props;
    return (
      <Container>
        <Row>
          <Col>
            Home page is working!<br />
            List of users from Drupal:<br />
            <ul>
              {users.map(user => <li key={user.id}>
                {user.name} (id: {user.id})
                {user.edit_link ? <a href={user.edit_link} target="_blank" rel="noopener noreferrer">Edit</a> : null}
              </li>)}
            </ul>
          </Col>
        </Row>
      </Container>
    );
  }
}

HomePage.propTypes = {
  users: PropTypes.arrayOf(PropTypes.shape({
    name: PropTypes.string,
    id: PropTypes.string,
  })),
};

HomePage.defaultProps = {
  users: [],
};

export default HomePage;
